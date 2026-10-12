#!/usr/bin/env python3
"""Test packaged callbacks against measured 64-byte VIP tail burst."""
from pathlib import Path
import re,subprocess,tempfile
patch=(Path(__file__).resolve().parents[1]/'patches-6.12/0009-nexell-s5p6818-camera-capture.patch').read_text()
part=patch.split('+++ b/drivers/media/platform/nexell/s5p6818-capture.c\n',1)[1].split('--- a/',1)[0]
s='\n'.join(line[1:] for line in part.splitlines() if line.startswith('+'))
def fn(name):
 a=re.search(r'static [^\n]+\b'+name+r'\(',s).start();b=s.index('{',a);depth=1;e=b+1
 while depth:
  depth+=(s[e]=='{')-(s[e]=='}');e+=1
 return s[a:e]
prefix=r"""
#include <assert.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#define MEDIA_BUS_FMT_UYVY8_1X16 1
#define V4L2_PIX_FMT_YUYV 2
#define V4L2_FIELD_NONE 3
struct device {};
enum v4l2_subdev_format_whence {V4L2_SUBDEV_FORMAT_TRY,V4L2_SUBDEV_FORMAT_ACTIVE};
struct v4l2_pix_format {unsigned width,height,pixelformat,field,bytesperline,sizeimage,colorspace,ycbcr_enc,quantization,xfer_func;};
struct v4l2_subdev_format {int which,pad;struct {unsigned width,height,code,field,colorspace,ycbcr_enc,quantization,xfer_func;} format;};
struct nx_capture {void *sensor;int sensor_pad;struct v4l2_pix_format format;};
struct vb2_queue {struct nx_capture *cap;};
struct vb2_buffer {struct vb2_queue *vb2_queue;unsigned capacity,payload;};
static struct nx_capture *vb2_get_drv_priv(struct vb2_queue *q) {return q->cap;}
static unsigned vb2_plane_size(struct vb2_buffer *b,int p) {(void)p;return b->capacity;}
static void vb2_set_plane_payload(struct vb2_buffer *b,int p,unsigned n) {(void)p;b->payload=n;}
static int mock_fmt(struct v4l2_subdev_format *f) {(void)f;return 0;}
#define v4l2_subdev_call_state_try(s,p,o,f) mock_fmt(f)
#define v4l2_subdev_call_state_active(s,p,o,f) mock_fmt(f)
"""
suffix=r"""
int main(void) {
 struct nx_capture c={.sensor=(void*)1};struct v4l2_pix_format pix={.width=1280,.height=960};
 assert(nx_sensor_fmt(&c,&pix,V4L2_SUBDEV_FORMAT_ACTIVE)==0);
 /* Independent measured data length plus one 64-byte DMA burst. */
 assert(pix.bytesperline==2560 && pix.sizeimage==2457664);c.format=pix;
 struct vb2_queue q={&c};unsigned planes=0,count=4,sizes[1]={0};
 assert(nx_queue_setup(&q,&count,&planes,sizes,0)==0 && planes==1 && sizes[0]==2457664);
 sizes[0]=2457600;assert(nx_queue_setup(&q,&count,&planes,sizes,0)==-EINVAL);
 sizes[0]=2457664;assert(nx_queue_setup(&q,&count,&planes,sizes,0)==0);
 struct vb2_buffer b={.vb2_queue=&q,.capacity=2457600};
 assert(nx_buffer_prepare(&b)==-EINVAL);b.capacity=2457664;
 assert(nx_buffer_prepare(&b)==0 && b.payload==2457600);
 pix.width=2592;pix.height=1944;assert(nx_sensor_fmt(&c,&pix,V4L2_SUBDEV_FORMAT_TRY)==0);
 assert(pix.sizeimage==2592U*1944*2+64);
 puts("PASS: actual format/queue/import callbacks reserve DMA tail and report visible payload only");
}
"""
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'test.c').write_text(prefix+'\n'.join(x for x in s.splitlines() if x.startswith('#define '))+'\n'+'\n'.join(fn(n) for n in ['nx_queue_setup','nx_buffer_prepare','nx_sensor_fmt'])+suffix)
 subprocess.run(['cc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fsanitize=undefined',str(p/'test.c'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
