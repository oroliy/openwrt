#!/usr/bin/env python3
"""Exercise actual packaged DMA queue/IRQ callbacks with fake MMIO/vb2."""
from pathlib import Path
import re,subprocess,tempfile
patch=(Path(__file__).resolve().parents[1]/'patches-6.12/0009-nexell-s5p6818-camera-capture.patch').read_text()
part=patch.split('+++ b/drivers/media/platform/nexell/s5p6818-capture.c\n',1)[1].split('--- a/',1)[0]
s='\n'.join(line[1:] for line in part.splitlines() if line.startswith('+'))
def function(name):
    start=re.search(r'static [^\n]+\b'+name+r'\(',s).start()
    brace=s.index('{',start);level=1;end=brace+1
    while level:
        level+=(s[end]=='{')-(s[end]=='}');end+=1
    return s[start:end]
constants='\n'.join(x for x in s.splitlines() if x.startswith('#define '))
prefix=r'''
#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stddef.h>
typedef uint32_t u32;
typedef uint64_t dma_addr_t;
typedef int irqreturn_t;
#define IRQ_NONE 0
#define IRQ_HANDLED 1
#define BIT(x) (1U<<(x))
#define lower_32_bits(x) ((uint32_t)(x))
#define V4L2_FIELD_NONE 1
#define container_of(p,t,m) ((t*)((char*)(p)-offsetof(t,m)))
struct list_head { struct list_head *next,*prev; };
static void init(struct list_head *l) {l->next=l;l->prev=l;}
static int list_empty(struct list_head *l) {return l->next==l;}
static void list_del(struct list_head *l) {l->prev->next=l->next;l->next->prev=l->prev;}
static void list_add_tail(struct list_head *l,struct list_head *h) {l->next=h;l->prev=h->prev;h->prev->next=l;h->prev=l;}
#define list_first_entry(h,t,m) container_of((h)->next,t,m)
#define list_for_each_entry_safe(p,n,h,m) for(p=container_of((h)->next,__typeof__(*p),m),n=container_of(p->m.next,__typeof__(*p),m);&p->m!=(h);p=n,n=container_of(n->m.next,__typeof__(*n),m))
enum vb2_buffer_state {VB2_BUF_STATE_DONE,VB2_BUF_STATE_ERROR,VB2_BUF_STATE_QUEUED};
struct vb2_buffer { dma_addr_t dma;uint64_t timestamp;unsigned int completions;enum vb2_buffer_state state; };
struct vb2_v4l2_buffer {struct vb2_buffer vb2_buf;unsigned int sequence,field;};
struct nx_buffer {struct vb2_v4l2_buffer vb;struct list_head list;};
struct nx_capture {void *vip;struct list_head buffers;struct nx_buffer *active;dma_addr_t scratch_dma;bool powered,streaming,stopping;int stop_done,lock;unsigned int sequence;};
static unsigned int mmio_reads;
static unsigned int barriers;
static void wmb(void) {++barriers;}
static void complete(int *c) {++*c;}
#define spin_lock_irqsave(l,f) do {(void)(l);(f)=0;} while(0)
#define spin_unlock_irqrestore(l,f) do {(void)(l);(void)(f);} while(0)
static uint64_t ktime_get_ns(void) {static uint64_t t;return ++t;}
static dma_addr_t vb2_dma_contig_plane_dma_addr(struct vb2_buffer *b,int p) {(void)p;return b->dma;}
static void vb2_buffer_done(struct vb2_buffer *b,enum vb2_buffer_state state) {assert(b->completions==0);b->completions++;b->state=state;}
static u32 readl(void *p) {mmio_reads++;return *(u32*)p;}
static void writel(u32 v,void *p) {*(u32*)p=v;}
'''
suffix=r'''
int main(void) {
    u32 regs[1024]={0};struct nx_capture c={.vip=regs,.scratch_dma=0x70000000};
    struct nx_buffer a={.vb.vb2_buf.dma=0x50000000},b={.vb.vb2_buf.dma=0x51000000};
    init(&c.buffers);regs[VIP_ODINT/4]=1;
    assert(nx_irq(0,&c)==IRQ_NONE && mmio_reads==0); /* clocks off: no register read */
    c.powered=true;regs[VIP_ODINT/4]=0;assert(nx_irq(0,&c)==IRQ_NONE);
    list_add_tail(&a.list,&c.buffers);list_add_tail(&b.list,&c.buffers);
    nx_dma_target(&c);assert(c.active==&a && regs[VIP_ADDR/4]==0x50000000);
    c.streaming=true;regs[VIP_ODINT/4]=0x101;
    assert(nx_irq(0,&c)==IRQ_HANDLED);assert(a.vb.vb2_buf.completions==1 && a.vb.vb2_buf.state==VB2_BUF_STATE_DONE && a.vb.sequence==0);
    assert(c.active==&b && regs[VIP_ADDR/4]==0x51000000 && regs[VIP_ENABLE/4]==0x102);
    assert(nx_irq(0,&c)==IRQ_HANDLED);assert(b.vb.vb2_buf.completions==1 && b.vb.sequence==1);
    assert(!c.active && regs[VIP_ADDR/4]==0x70000000); /* never DMA into returned buffer */
    assert(nx_irq(0,&c)==IRQ_HANDLED);assert(c.sequence==3 && !c.active);
    a.vb.vb2_buf.completions=0;list_add_tail(&a.list,&c.buffers);
    assert(nx_irq(0,&c)==IRQ_HANDLED && c.active==&a);
    assert(nx_irq(0,&c)==IRQ_HANDLED && a.vb.sequence==4 && a.vb.vb2_buf.completions==1);
    assert(a.vb.vb2_buf.timestamp>b.vb.vb2_buf.timestamp);
    a.vb.vb2_buf.completions=b.vb.vb2_buf.completions=0;
    list_add_tail(&a.list,&c.buffers);list_add_tail(&b.list,&c.buffers);nx_dma_target(&c);
    c.stopping=true;c.streaming=true;regs[VIP_CONFIG/4]=1;
    unsigned seq=c.sequence;
    assert(nx_irq(0,&c)==IRQ_HANDLED);
    assert(!c.streaming && c.stop_done==1 && c.active==&a && barriers==1);
    assert(c.sequence==seq && a.vb.vb2_buf.completions==0 && b.vb.vb2_buf.completions==0);
    assert(regs[VIP_ENABLE/4]==0 && regs[VIP_CONFIG/4]==0 && regs[VIP_ODINT/4]==1);
    nx_return_buffers(&c,VB2_BUF_STATE_ERROR);
    assert(!c.active && list_empty(&c.buffers));assert(a.vb.vb2_buf.state==VB2_BUF_STATE_ERROR && b.vb.vb2_buf.state==VB2_BUF_STATE_ERROR);
    nx_return_buffers(&c,VB2_BUF_STATE_ERROR); /* idempotent empty cleanup */
    a.vb.vb2_buf.completions=0;list_add_tail(&a.list,&c.buffers);
    nx_return_buffers(&c,VB2_BUF_STATE_QUEUED);assert(a.vb.vb2_buf.state==VB2_BUF_STATE_QUEUED);
    puts("PASS: frame-boundary stop, retain DMA ownership until shutdown, actual DMA/IRQ callbacks, queue ordering, timestamps, scratch underrun, powered-off IRQ and failed-start/stop buffer returns");
}
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);(p/'test.c').write_text(prefix+constants+'\n'+'\n'.join(function(n) for n in ['nx_dma_target','nx_irq','nx_return_buffers'])+suffix)
    subprocess.run(['cc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fsanitize=undefined',str(p/'test.c'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
