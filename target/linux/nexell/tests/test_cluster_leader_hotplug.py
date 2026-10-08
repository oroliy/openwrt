#!/usr/bin/env python3
"""Host tests of extracted applied PSCI functions; no kernel/board operation."""
import argparse, hashlib, json, pathlib, re, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[4]
KERNELS = sorted(ROOT.glob('build_dir/target-aarch64*/linux-nexell*/linux-6.12.*'))
DEFAULT_KERNEL = KERNELS[0] if len(KERNELS) == 1 else None
NAMES = ('cpu_psci_x6818_cluster_leader', 'cpu_psci_cpu_can_disable', 'cpu_psci_cpu_disable')

def extract_function(source, name):
    match = re.search(r'^static\s+(?:bool|int)\s+' + name + r'\([^\n]*\)\s*\{', source, re.M)
    if not match:
        raise RuntimeError('applied function absent: ' + name)
    # These functions contain no brace-bearing string literals or comments.
    start = source.index('{', match.start()); depth = 1; end = start + 1
    while depth:
        if end >= len(source):
            raise RuntimeError('unbalanced function: ' + name)
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    guards = []
    for line in source[:match.start()].splitlines():
        if re.match(r'^#\s*(if|ifdef|ifndef)\b', line): guards.append(line.strip())
        elif re.match(r'^#\s*endif\b', line): guards.pop()
    if '#ifdef CONFIG_HOTPLUG_CPU' not in guards:
        raise RuntimeError(name + ' is not enclosed by the production HOTPLUG guard')
    return source[match.start():end]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--kernel-dir', type=pathlib.Path, default=DEFAULT_KERNEL,
                        help='prepared Nexell ARM64 Linux tree')
    parser.add_argument('--output', type=pathlib.Path, help='optional JSON evidence path')
    args = parser.parse_args()
    if args.kernel_dir is None:
        parser.error('provide --kernel-dir after preparing the Nexell ARM64 kernel')
    kernel = args.kernel_dir
    source_path = kernel / 'arch/arm64/kernel/psci.c'
    source = source_path.read_text()
    functions = '\n\n'.join(extract_function(source, name) for name in NAMES)
    header = (kernel/'arch/arm64/include/asm/cputype.h').read_text()
    macro_start = header.index('#define MPIDR_LEVEL_BITS_SHIFT')
    macro_end = header.index('\n', header.index('((mpidr >> MPIDR_LEVEL_SHIFT(level)) & MPIDR_LEVEL_MASK)', macro_start))
    macros = header[macro_start:macro_end]
    dt_path = kernel/'arch/arm64/boot/dts/nexell/s5p6818.dtsi'
    dt = dt_path.read_text()
    mapping = {int(a): int(b,16) for a,b in re.findall(r'cpu(\d+): cpu@[^\s]+\s*\{[^}]*?reg\s*=\s*<0x0\s+(0x[0-9a-f]+)>;',dt,re.S)}
    if sorted(mapping) != list(range(8)):
        raise RuntimeError('cannot establish exact eight-core DT mapping')
    expected = {0:0,1:1,2:2,3:3,4:0x100,5:0x101,6:0x102,7:0x103}
    if mapping != expected:
        raise RuntimeError('DT mapping changed: review guard policy before running')
    prefix = '''#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
static uint64_t cpu_map[8] = {MAP};
static bool board_matches, tos_resident;
static unsigned int tos_calls, off_calls, map_calls;
struct { void (*cpu_off)(void); } psci_ops;
void fake_cpu_off(void) { off_calls++; }
bool of_machine_is_compatible(const char *name) {
 assert(!strcmp(name,"nexell,x6818")); return board_matches;
}
uint64_t cpu_logical_map(unsigned int cpu) { assert(cpu<8); map_calls++; return cpu_map[cpu]; }
bool psci_tos_resident_on(unsigned int cpu) { assert(cpu<8); tos_calls++; return tos_resident; }
'''.replace('MAP', ','.join(hex(mapping[i]) for i in range(8)))
    checks = '''
int main(void) {
#ifdef CONFIG_HOTPLUG_CPU
 unsigned int cases=0;
 for (unsigned int permuted=0;permuted<2;permuted++) {
  if(permuted) { uint64_t t=cpu_map[0]; cpu_map[0]=cpu_map[5];cpu_map[5]=t; t=cpu_map[1];cpu_map[1]=cpu_map[4];cpu_map[4]=t; }
  for(unsigned int board=0;board<2;board++)
   for(unsigned int cpu=0;cpu<8;cpu++)
    for(unsigned int resident=0;resident<2;resident++)
     for(unsigned int off=0;off<2;off++) {
      board_matches=board;tos_resident=resident;psci_ops.cpu_off=off?fake_cpu_off:NULL;
      bool leader=board && (cpu_map[cpu]==0 || cpu_map[cpu]==0x100);
      map_calls=0;assert(cpu_psci_x6818_cluster_leader(cpu)==leader);assert(map_calls==(board?1U:0U));
      tos_calls=0;assert(cpu_psci_cpu_can_disable(cpu)==(!leader && !resident));assert(tos_calls==(leader?0U:1U));
      tos_calls=0;int result=cpu_psci_cpu_disable(cpu);
      int expected=leader || !off ? -EOPNOTSUPP : resident ? -EPERM : 0;
      assert(result==expected);assert(tos_calls==(!leader && off?1U:0U));assert(off_calls==0);cases++;
     }
 }
 printf("PASS: %u cases; DT and permuted logical maps, board scope, TOS, missing CPU_OFF; no CPU_OFF invocation\\n",cases);
#else
 assert(psci_ops.cpu_off==NULL);
 printf("PASS: CONFIG_HOTPLUG_CPU=n excludes all three extracted functions\\n");
#endif
 return 0;
}
'''
    evidence={'source':str(source_path.resolve()),'source_sha256':hashlib.sha256(source.encode()).hexdigest(),
              'extracted_functions_sha256':hashlib.sha256(functions.encode()).hexdigest(),
              'mpidr_macros_sha256':hashlib.sha256(macros.encode()).hexdigest(),
              'dt':str(dt_path),'dt_sha256':hashlib.sha256(dt.encode()).hexdigest(),'dt_cpu_map':mapping,'results':[]}
    with tempfile.TemporaryDirectory(prefix='x6818-psci-host-') as tmp:
        tmp=pathlib.Path(tmp); c=tmp/'test.c';c.write_text(prefix+macros+'\n#ifdef CONFIG_HOTPLUG_CPU\n'+functions+'\n#endif\n'+checks)
        for enabled in [True,False]:
            binary=tmp/('hotplug-on' if enabled else 'hotplug-off')
            command=['cc','-std=c11','-Wall','-Wextra','-Werror','-O0']+(['-DCONFIG_HOTPLUG_CPU'] if enabled else [])+[str(c),'-o',str(binary)]
            subprocess.run(command,check=True)
            out=subprocess.check_output([str(binary)],text=True).strip();print(out,flush=True)
            symbols=subprocess.check_output(['nm',str(binary)],text=True)
            for name in NAMES:
                if bool(re.search(r'\b'+name+r'$',symbols,re.M)) != enabled:
                    raise RuntimeError('HOTPLUG symbol gating failed: '+name)
            evidence['results'].append({'CONFIG_HOTPLUG_CPU':enabled,'stdout':out,'symbol_gating':True})
    evidence['success'] = True
    if args.output:
        args.output.write_text(json.dumps(evidence, indent=2) + '\n')
        print('Evidence:', args.output)

if __name__=='__main__': main()
