#!/usr/bin/env python3
"""Regress the actual packaged TMU get_temp against board register snapshots."""
from pathlib import Path
import subprocess
import tempfile

patch = Path(__file__).resolve().parents[1] / "patches-6.12/0008-nexell-s5p6818-temperature-monitor.patch"
text = patch.read_text().split("+++ b/drivers/thermal/nexell-s5p6818-thermal.c\n", 1)[1]
text = text.split("--- /dev/null", 1)[0]
source = "\n".join(line[1:] for line in text.splitlines() if line.startswith("+"))
function = source[source.index("static int nexell_tmu_get_temp"):source.index("\nstatic const struct thermal_zone_device_ops")]
PREFIX = r"""
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
typedef uint32_t u32;
#define BIT(x) (1U << (x))
#define TMU_STATUS 0x28
#define TMU_CURRENT_TEMP 0x40
struct nexell_tmu { void *base; int trim; };
struct thermal_zone_device { struct nexell_tmu *data; };
static void *thermal_zone_device_priv(struct thermal_zone_device *tz) { return tz->data; }
static u32 readl(void *p) { return *(u32 *)p; }
"""
SUFFIX = r"""
int main(void) {
    u32 regs[0x104 / 4] = {0};
    struct nexell_tmu tmu = { .base = regs, .trim = 45 };
    struct thermal_zone_device zone = { .data = &tmu };
    int temp = 123456;
    assert(nexell_tmu_get_temp(&zone, &temp) == -ENODATA && temp == 123456);
    regs[TMU_STATUS / 4] = 0x1a0; /* Real active sensing status. */
    regs[TMU_CURRENT_TEMP / 4] = 45;
    assert(!nexell_tmu_get_temp(&zone, &temp) && temp == 25000);
    regs[TMU_CURRENT_TEMP / 4] = 70;
    assert(!nexell_tmu_get_temp(&zone, &temp) && temp == 50000);
    tmu.trim = 55;
    assert(!nexell_tmu_get_temp(&zone, &temp) && temp == 40000);
    regs[TMU_CURRENT_TEMP / 4] = 20;
    assert(!nexell_tmu_get_temp(&zone, &temp) && temp == -10000);
    regs[TMU_CURRENT_TEMP / 4] = 0;
    assert(nexell_tmu_get_temp(&zone, &temp) == -ENODATA);
    regs[TMU_CURRENT_TEMP / 4] = 255;
    assert(nexell_tmu_get_temp(&zone, &temp) == -ENODATA);
    tmu.trim = 42;
    regs[TMU_CURRENT_TEMP / 4] = 0x45;
    assert(!nexell_tmu_get_temp(&zone, &temp) && temp == 52000);
    regs[TMU_STATUS / 4] = 0x70;
    assert(!nexell_tmu_get_temp(&zone, &temp) && temp == 52000);
    regs[TMU_STATUS / 4] = 1;
    assert(!nexell_tmu_get_temp(&zone, &temp) && temp == 52000);
    tmu.trim = 46;
    regs[TMU_CURRENT_TEMP / 4] = 0xff;
    assert(nexell_tmu_get_temp(&zone, &temp) == -ENODATA && temp == 52000);
    puts("PASS: actual driver get_temp, factory trim, units, negative temperature, active sensing status and invalid ADC");
}
"""
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "test.c").write_text(PREFIX + function + "\n" + SUFFIX)
    subprocess.run(["cc", "-Wall", "-Wextra", "-Werror", "-fsanitize=undefined", str(root / "test.c"), "-o", str(root / "test")], check=True)
    subprocess.run([str(root / "test")], check=True)
