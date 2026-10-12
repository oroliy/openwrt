#!/usr/bin/env python3
"""Exercise actual packaged stream-off ordering and bounded missing-frame path."""
from pathlib import Path
import re,subprocess,tempfile
patch=(Path(__file__).resolve().parents[1]/'patches-6.12/0009-nexell-s5p6818-camera-capture.patch').read_text()
part=patch.split('+++ b/drivers/media/platform/nexell/s5p6818-capture.c\n',1)[1].split('--- a/',1)[0]
s='\n'.join(line[1:] for line in part.splitlines() if line.startswith('+'))
a=re.search(r'static void nx_stop_streaming\(',s).start();brace=s.index('{',a);n=1;z=brace+1
while n:n+=(s[z]=='{')-(s[z]=='}');z+=1
function=s[a:z]
prefix=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
struct video_device {void *pipe;};
struct nx_capture {bool powered,streaming,stopping;int stop_done,lock;void *sensor,*dev,*scratch;unsigned long scratch_dma;struct {unsigned sizeimage;} format;struct video_device video;};
struct vb2_queue {struct nx_capture *cap;};
static struct nx_capture *current;
static int order,warning,wait_ok;
#define VB2_BUF_STATE_ERROR 2
#define spin_lock_irqsave(l,f) do {(void)(l);f=0;} while(0)
#define spin_unlock_irqrestore(l,f) do {(void)(l);(void)(f);} while(0)
#define reinit_completion(c) (*(c)=0)
#define msecs_to_jiffies(x) (x)
#define dev_warn(d,...) do {(void)(d);warning++;} while(0)
static struct nx_capture *vb2_get_drv_priv(struct vb2_queue *q){return q->cap;}
static int wait_for_completion_timeout(int *done,int ms){assert(ms==2000 && current->stopping);assert(order++==0);if(wait_ok){*done=1;current->streaming=false;}return wait_ok;}
static void nx_hw_stop(struct nx_capture *c){assert(order++==1);if(wait_ok)assert(!c->streaming);c->streaming=false;c->powered=false;}
static int sensor_stop(int en){assert(!en && !current->powered && !current->streaming && order++==2);return 0;}
#define v4l2_subdev_call(s,v,f,en) ((void)(s),sensor_stop(en))
static void video_device_pipeline_stop(struct video_device *v){(void)v;assert(order++==3);}
static void nx_return_buffers(struct nx_capture *c,int state){assert(!c->powered && state==VB2_BUF_STATE_ERROR && order++==4);}
static void dma_free_coherent(void *d,unsigned n,void *p,unsigned long a){(void)d;(void)a;assert(n==64 && order++==5);free(p);}
'''
suffix=r'''
int main(void){
 struct nx_capture c={.format.sizeimage=64,.sensor=(void*)1};struct vb2_queue q={&c};current=&c;
 for(wait_ok=0;wait_ok<2;wait_ok++){
  c.powered=true;c.streaming=true;c.stopping=false;c.scratch=malloc(64);assert(c.scratch);order=warning=0;
  nx_stop_streaming(&q);assert(order==6 && !c.powered && !c.streaming && !c.scratch && warning==!wait_ok);
  order=0;nx_stop_streaming(&q);assert(!order);
 }
 puts("PASS: actual stream-off callback waits for frame, shuts receiver before sensor, returns/frees buffers after hardware stop, bounded timeout and inactive idempotence");
}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'test.c').write_text(prefix+function+suffix)
 subprocess.run(['cc','-Wall','-Wextra','-Werror','-fsanitize=undefined',str(p/'test.c'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
