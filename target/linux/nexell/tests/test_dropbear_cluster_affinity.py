#!/usr/bin/env python3
"""Run the actual init command branch through taskset and a harmless daemon."""
from pathlib import Path
import os, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[4]
source = (ROOT / 'package/network/services/dropbear/files/dropbear.init').read_text()
start = source.index('\tprocd_open_instance\n\t# Keep the x6818 SSH')
end = source.index('\n\tif [ -n "${iface}" ]', start)
branch = source[start:end]
with tempfile.TemporaryDirectory() as td:
    root = Path(td); program = root / 'daemon'; c = root / 'daemon.c'
    c.write_text('''#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
int main(void)
{
    cpu_set_t mask;
    if (sched_getaffinity(0, sizeof(mask), &mask)) return 1;
    for (int cpu = 0; cpu < CPU_SETSIZE; cpu++) {
        if (CPU_ISSET(cpu, &mask)) printf("%d ", cpu);
    }
    return 0;
}
''')
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(program)], check=True)
    script = root / 'branch.sh'
    script.write_text('''#!/bin/sh
procd_open_instance() { :; }
procd_set_param() { printf '%s\\0' "$@"; }
cat() { [ "$FIXTURE_BOARD" != missing ] || return 1; printf '%s\\n' "$FIXTURE_BOARD"; }
fixture() {
local pid_file=/tmp/fixture.pid
''' + branch + '\n}\nfixture\n')
    inherited = os.sched_getaffinity(0)
    assert {0, 1, 2, 3} <= inherited
    for board in ['nexell,x6818', 'nexell,other', 'missing']:
        env = dict(os.environ, FIXTURE_BOARD=board, PROG=str(program))
        result = subprocess.run(['/bin/sh', str(script)], env=env, capture_output=True, check=True)
        argv = result.stdout.decode().rstrip('\0').split('\0')
        assert argv.pop(0) == 'command'
        if board == 'nexell,x6818':
            assert argv[:3] == ['/usr/bin/taskset', '-c', '0-3']
        else:
            assert argv[0] == str(program)
        actual = subprocess.check_output(argv, text=True)
        expected = {0, 1, 2, 3} if board == 'nexell,x6818' else inherited
        assert {int(cpu) for cpu in actual.split()} == expected
        assert os.sched_getaffinity(0) == inherited
print('PASS: real init command/exec confines x6818 daemon only; other and unidentified boards retain inherited affinity')
