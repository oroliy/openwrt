from pathlib import Path
import re,subprocess,tempfile
root=Path('/home/liy/workdir/port')
patch=(Path(__file__).resolve().parents[1]/"patches-6.12/0009-nexell-s5p6818-camera-capture.patch").read_text()
part=patch.split("+++ b/drivers/media/platform/nexell/s5p6818-capture.c\n",1)[1].split("--- a/",1)[0]
s="\n".join(line[1:] for line in part.splitlines() if line.startswith("+"))
def function(name):
    start=re.search(r'static [^\n]+\b'+name+r'\(',s).start()
    brace=s.index('{',start); level=1; end=brace+1
    while level:
        level += (s[end]=='{')-(s[end]=='}');end+=1
    return s[start:end]
constants='\n'.join(x for x in s.splitlines() if x.startswith('#define '))
prefix=r'''
#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#define spin_lock_irqsave(l,f) do {(void)(l);(f)=0;} while(0)
#define spin_unlock_irqrestore(l,f) do {(void)(l);(void)(f);} while(0)
typedef uint32_t u32;
#define BIT(x) (1U<<(x))
#define ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))
struct nx_capture { void *csi,*vip,*sram; int clocks[3];struct {void *rstc;} resets[6];bool powered,streaming,irq_enabled,clocks_enabled;int irq,lock; struct {unsigned int width,height,bytesperline;} format; };
static int clk_failure,assert_failure,deassert_failure,enabled,disabled,writes,stop_step,pll_failure;
static void *pll_register;
static int clk_bulk_prepare_enable(unsigned n,void *a) { (void)n;(void)a;if(clk_failure)return -EIO;enabled++;return 0; }
static void clk_bulk_disable_unprepare(unsigned n,void *a) { (void)n;(void)a;if(stop_step)assert(stop_step==2);disabled++; }
static int reset_control_bulk_assert(unsigned n,void *a) { (void)n;(void)a;return assert_failure ? -EIO:0; }
static int reset_control_bulk_deassert(unsigned n,void *a) { (void)n;(void)a;return deassert_failure ? -EIO:0; }
static void disable_irq(int irq) {(void)irq;assert(stop_step==0);stop_step=1;}
static void synchronize_irq(int irq) {(void)irq;assert(stop_step==1);stop_step=2;}
static void wmb(void) {}
static void usleep_range(int a,int b) { (void)a;(void)b; }
static void writel(u32 v,void *p) { if (!(pll_failure && p==pll_register)) *(u32*)p=v;writes++; }
static u32 readl(void *p) { return *(u32*)p; }
'''
suffix=r'''
int main(void) {
    u32 csi[1024]={0},vip[1024]={0},sram=0x1ff81;
    struct nx_capture c={.csi=csi,.vip=vip,.sram=&sram,.format={1280,960,2560}};
    /* Independently specified offsets from the vendor MIPI/VIP layouts. */
    assert(MIPI_PLL==0x14c && MIPI_PLLTMR==0x150 && MIPI_PHY==0x154 && MIPI_PHY1==0x158);
    assert(VIP_FORMAT==0x288 && VIP_ADDR==0x28c && VIP_STRIDE==0x290 && VIP_SCAN==0x2c0 && VIP_PORT==0x2d8);
    assert(!nx_hw_start(&c));
    assert(sram==0x1ff87); /* only the MIPI SRAM EMA field changes */
    assert(vip[0x010/4]==0 && vip[0x014/4]==0);
    assert(csi[0x44/4]==((1280U<<16)|960));
    assert(csi[0x40/4]%256==(0x1e<<2)); /* YUV422 DT, VC0 */
    assert(csi[0x18/4]==BIT(25)); /* channel1 full YUV422 */
    assert((csi[0]&0xd)==5 && (csi[0]&(3<<22))==(2<<22));
    assert((csi[1]&31)==7); /* clock + exactly two data lanes */
    assert(csi[0x14c/4] & BIT(23));
    assert(csi[0x24c/4]==0); /* Do not use erroneous DSI offset. */
    assert(vip[0x208/4]==1280 && vip[0x20c/4]==960);
    assert(vip[0x214/4]==1280 && vip[0x21c/4]==960);
    assert(vip[0x2d8/4]==1); /* CSI is wired to port B, not external port A. */
    assert(vip[0x288/4]==3 && vip[0x290/4]==2560);
    assert(vip[0x200/4]==0 && !(vip[0]&1)); /* DMA gated until buffers installed */
    csi[0x14c/4]=0x128abcde; csi[0x150/4]=123; csi[0x154/4]=456;
    assert(!nx_hw_start(&c));assert(csi[0x14c/4]==0x128abcde && csi[0x150/4]==123 && csi[0x154/4]==456);
    c.format.width=2592;c.format.height=1944;c.format.bytesperline=5184;
    assert(!nx_hw_start(&c));assert(vip[0x214/4]==2592 && vip[0x21c/4]==1944 && vip[0x290/4]==5184);
    assert(enabled==1 && c.clocks_enabled); /* repeated start retains one clock reference */
    c.clocks_enabled=false;
    int oldwrites=writes;
    clk_failure=1;assert(nx_hw_start(&c)==-EIO && writes==oldwrites && disabled==0);clk_failure=0;
    assert_failure=1;assert(nx_hw_start(&c)==-EIO && writes==oldwrites && disabled==1);assert_failure=0;
    deassert_failure=1;assert(nx_hw_start(&c)==-EIO && writes==oldwrites && disabled==2);
    deassert_failure=0;pll_register=&csi[0x14c/4];csi[0x14c/4]=0;
    pll_failure=1;vip[0x2d8/4]=0x55;
    assert(nx_hw_start(&c)==-EIO && vip[0x2d8/4]==0x55); /* PLL write did not stick: never arm VIP. */
    pll_failure=0;
    c.powered=c.streaming=c.irq_enabled=true;vip[0]=BIT(8)|BIT(0);vip[VIP_ENABLE/4]=BIT(8)|BIT(1);
    int before_stop=disabled;
    nx_hw_stop(&c);
    assert(!c.powered && !c.streaming && !c.irq_enabled && stop_step==2 && disabled==before_stop);
    nx_irq_disable(&c); /* balanced stop is idempotent after a failed start too */
    assert(vip[VIP_ODINT/4]==BIT(0)); /* W1C pending with mask off */
    assert(vip[VIP_ENABLE/4]==0 && !(vip[0]&1) && !(csi[0]&1) && !(csi[1]&31));
    stop_step=0;enabled=disabled=0;c.clocks_enabled=false;
    assert(!nx_hw_start(&c) && enabled==1 && c.clocks_enabled);
    c.irq_enabled=true;nx_hw_stop(&c);assert(enabled==1 && disabled==0 && c.clocks_enabled);
    stop_step=0;assert(!nx_hw_start(&c) && enabled==1);
    c.irq_enabled=true;nx_hw_stop(&c);assert(disabled==0 && c.clocks_enabled);
    puts("PASS: clock retention/refcount across starts/stops and actual nx_hw_start/stop, vendor offsets, VC/lane/DMA layout, PLL preservation, gated startup and clock/reset failures");
}
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);(p/'test.c').write_text(prefix+constants+'\n'+function('nx_hw_start')+'\n'+function('nx_irq_disable')+'\n'+function('nx_hw_stop')+'\n'+suffix)
    subprocess.run(['cc','-Wall','-Wextra','-Werror','-fsanitize=undefined',str(p/'test.c'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
