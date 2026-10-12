#!/usr/bin/env python3
"""Exercise the actual USB resource reservation and register configuration."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
patch = root / 'patches-6.12/0010-phy-nexell-reserve-only-usb-tieoff-registers.patch'
port = root.parents[3]
source = port / 'linux-lts/drivers/phy/nexell/phy-s5p6818-usb2.c'
s = source.read_text()

def function(name):
    start = re.search(r'static [^\n]+\b' + name + r'\(', s).start()
    brace = s.index('{', start)
    level, end = 1, brace + 1
    while level:
        level += (s[end] == '{') - (s[end] == '}')
        end += 1
    return s[start:end]

constants = s[s.index('#define NX_USB_TIEOFF_OFFSET'):s.index('enum nexell_usb2_type')]
probe = function('nexell_usb2_probe')
mapping = probe[probe.index('\tres = platform_get_resource'):probe.index('\n\tusb->clk =')]
prefix = r'''
#include <assert.h>
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
typedef uint32_t u32;
#define BIT(x) (1U << (x))
#define GENMASK(h,l) ((~0U << (l)) & (~0U >> (31-(h))))
#define IORESOURCE_MEM 1
#define IS_ERR(p) ((uintptr_t)(p) >= (uintptr_t)-4095)
#define PTR_ERR(p) ((int)(intptr_t)(p))
struct resource { uint64_t start,end; };
struct device { int unused; };
struct platform_device { struct device dev; struct resource *res; };
struct nexell_usb2 { void *tieoff; };
enum nexell_usb2_type { NEXELL_USB2_EHCI, NEXELL_USB2_OHCI };
static uint32_t regs[64];
static uint64_t claimed_start,claimed_end;
static int map_error;
static struct resource *platform_get_resource(struct platform_device *p,int type,int n)
{ assert(type==IORESOURCE_MEM && n==0);return p->res; }
static uint64_t resource_size(struct resource *r) {return r->end-r->start+1;}
static void *devm_ioremap_resource(struct device *d,struct resource *r) {
 (void)d; claimed_start=r->start;claimed_end=r->end;
 if(map_error)return (void*)(intptr_t)-EBUSY;
 /* The camera has already reserved its SRAM control word. */
 if(r->start<=0xc0011013ULL && r->end>=0xc0011010ULL)return (void*)(intptr_t)-EBUSY;
 assert(r->start>=0xc0011000ULL && r->end<0xc0011100ULL);
 return (char*)regs + r->start-0xc0011000ULL;
}
static u32 readl(void *p) {return *(u32*)p;}
static void writel(u32 v,void *p) {
 assert((char*)p>=(char*)regs+0x14 && (char*)p<=(char*)regs+0x24);
 *(u32*)p=v;
}
static void udelay(int n) {(void)n;}
'''
wrapper = 'static int map_usb(struct platform_device *pdev,struct nexell_usb2 *usb) {\nstruct device *dev=&pdev->dev;struct resource *res,usb_regs;\n'+mapping+'\nreturn 0;\n}\n'
suffix = r'''
int main(void) {
 struct resource r={0xc0011000ULL,0xc00110ffULL};
 struct platform_device p={.res=&r};struct nexell_usb2 usb={0};
 assert(!map_usb(&p,&usb));
 assert(claimed_start==0xc0011014ULL && claimed_end==0xc0011027ULL);
 regs[4]=0x1ff87;regs[0x28/4]=0xa5a5a5a5;
 for(int type=NEXELL_USB2_EHCI;type<=NEXELL_USB2_OHCI;type++) {
  nexell_usb2_configure(&usb,type);
  assert(regs[4]==0x1ff87 && regs[0x28/4]==0xa5a5a5a5);
  assert((regs[0x14/4] & (BIT(26)|BIT(25)))==(BIT(26)|BIT(25)));
  assert((regs[0x24/4] & (BIT(9)|BIT(8)))==(BIT(9)|BIT(8)));
  assert((regs[0x20/4] & (BIT(8)|BIT(7)))==BIT(7));
  u32 burst=type==NEXELL_USB2_EHCI ? BIT(28)|BIT(27)|BIT(26)|BIT(25):BIT(28)|BIT(27);
  assert((regs[0x1c/4] & (BIT(28)|BIT(27)|BIT(26)|BIT(25)))==burst);
 }
 map_error=1;assert(map_usb(&p,&usb)==-EBUSY);map_error=0;
 p.res=NULL;assert(map_usb(&p,&usb)==-EINVAL);p.res=&r;
 r.end=r.start+0x26;assert(map_usb(&p,&usb)==-EINVAL);
 r.end=r.start+0x27;assert(!map_usb(&p,&usb));
 puts("PASS: actual USB mapping/configuration, camera coexistence, unchanged physical register addresses, resource bounds and mapping error");
}
'''
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    (p/'test.c').write_text(prefix+constants+wrapper+function('nexell_usb2_set_fl_adj')+'\n'+function('nexell_usb2_configure')+'\n'+suffix)
    subprocess.run(['cc','-Wall','-Wextra','-Werror','-fsanitize=undefined',str(p/'test.c'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
# Also prove the OpenWrt patch produces the exact independently tested source.
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp); f=p/'drivers/phy/nexell/phy-s5p6818-usb2.c'
    f.parent.mkdir(parents=True);f.write_bytes(source.read_bytes())
    subprocess.run(['patch','-s','-R','-p1','-i',str(patch)],cwd=p,check=True)
    subprocess.run(['patch','-s','-p1','-i',str(patch)],cwd=p,check=True)
    assert f.read_bytes()==source.read_bytes()
print('PASS: OpenWrt patch matches tested Linux source')
