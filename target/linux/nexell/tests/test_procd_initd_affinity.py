#!/usr/bin/env python3
"""Exercise the packaged init-script workaround with real fork/CPU affinity."""
from pathlib import Path
import os, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[4]
patch = (ROOT / 'package/system/procd/patches/014-x6818-initd-cluster-affinity.patch').read_text()
added = '\n'.join(line[1:] for line in patch.splitlines() if line.startswith('+') and not line.startswith('+++'))
start = added.index('static int initd_cluster_affinity(void)')
function = added[start:added.index('\n\tif (initd_cluster_affinity())', start)]
# The fork parent returns before the new child-only restriction is called.
assert patch.index('@@ -') < patch.index('initd_cluster_affinity')
prelude = r'''
#define _GNU_SOURCE
#include <sched.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <assert.h>
static const char *fixture;
static int fixture_open(const char *path, int flags) {
    assert(!strcmp(path, "/proc/device-tree/compatible"));
    return open(fixture, flags);
}
#define open fixture_open
'''
main = r'''
#undef open
int main(int argc, char **argv) {
    cpu_set_t original, inherited, actual, expected;
    assert(argc == 3); fixture = argv[1];
    int policy = atoi(argv[2]);
    assert(!sched_getaffinity(0, sizeof(original), &original));
    inherited = original;
    if (policy == 3) { CPU_ZERO(&inherited); CPU_SET(4, &inherited); }
    if (policy == 4) { CPU_ZERO(&inherited); CPU_SET(1, &inherited); }
    assert(!sched_setaffinity(0, sizeof(inherited), &inherited));
    pid_t pid = fork(); assert(pid >= 0);
    if (!pid) {
        int result = initd_cluster_affinity();
        assert(!sched_getaffinity(0, sizeof(actual), &actual));
        expected = inherited;
        if (policy == 1 || policy == 4) {
            CPU_ZERO(&expected);
            for (int cpu = 0; cpu < 4; cpu++)
                if (CPU_ISSET(cpu, &inherited)) CPU_SET(cpu, &expected);
        }
        assert(CPU_EQUAL(&actual, &expected));
        assert(policy == 3 ? result == -1 : result == 0);
        _exit(0);
    }
    int status; assert(waitpid(pid, &status, 0) == pid);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(!sched_getaffinity(0, sizeof(actual), &actual));
    assert(CPU_EQUAL(&actual, &inherited));
    assert(!sched_setaffinity(0, sizeof(original), &original));
    return 0;
}
'''
assert {0, 1, 2, 3, 4} <= os.sched_getaffinity(0), 'run on a host with CPUs 0-4 available'
with tempfile.TemporaryDirectory() as td:
    directory = Path(td); source = directory / 'test.c'
    source.write_text(prelude + function + main)
    binary = directory / 'test'
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', '-DX6818_INITD_SINGLE_CLUSTER', str(source), '-o', str(binary)], check=True)
    for name, value, policy in [
        ('first', b'nexell,x6818\0nexell,s5p6818\0', 1),
        ('second', b'nexell,s5p6818\0nexell,x6818\0', 1),
        ('other', b'nexell,other\0', 0),
        ('unterminated', b'nexell,x6818', 0),
        ('no-cluster0', b'nexell,x6818\0', 3),
        ('narrow-inherited', b'nexell,x6818\0', 4),
    ]:
        fixture = directory / name; fixture.write_bytes(value)
        subprocess.run([str(binary), str(fixture), str(policy)], check=True)
    subprocess.run([str(binary), str(directory / 'missing'), '0'], check=True)
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(directory / 'first'), '0'], check=True)
print('PASS: real fork restricts x6818 child only, preserves parent/inherited limits, rejects empty mask; other boards/builds unchanged')
