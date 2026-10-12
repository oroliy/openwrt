#!/usr/bin/env python3
"""Actual rc.common/procd.sh enabled queries must not wait on startup locks."""
from pathlib import Path
import fcntl,os,signal,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[4]
source=(ROOT/'package/system/procd/files/procd.sh').read_text()
with tempfile.TemporaryDirectory() as td:
    r=Path(td)
    for p in ('lib/functions','usr/share/libubox','etc/init.d','etc/rc.d','var/lock'):(r/p).mkdir(parents=True,exist_ok=True)
    for p in ('lib/functions.sh','lib/functions/service.sh','usr/share/libubox/jshn.sh'):(r/p).touch()
    functions=(ROOT/'package/base-files/files/lib/functions.sh').read_text()
    start=functions.index('list_contains() {')
    (r/'lib/functions.sh').write_text(functions[start:functions.index('\n}',start)+2]+'\n')
    init=r/'etc/init.d/demo';init.write_text('START=99\nSTOP=10\nUSE_PROCD=1\nextra_command mutate mutate\nmutate() { echo changed > "$IPKG_INSTROOT/changed"; }\n')
    for prefix in ('S99','K10'):(r/'etc/rc.d'/f'{prefix}demo').symlink_to('../init.d/demo')
    script=r/'lib/functions/procd.sh'
    env=os.environ.copy();env['IPKG_INSTROOT']=td
    lock=(r/'var/lock/procd_demo.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX)
    def spawn(action):return subprocess.Popen(['busybox','ash',str(ROOT/'package/base-files/files/etc/rc.common'),str(init),action],env=env,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    def kill(p):os.killpg(p.pid,signal.SIGKILL);p.communicate()
    # Reproduce the old query waiting on a lock it does not need.
    script.write_text(source.replace('[ "${action:-}" = enabled ] || procd_lock','procd_lock',1))
    p=spawn('enabled')
    try:p.communicate(timeout=.5);raise AssertionError('baseline did not block')
    except subprocess.TimeoutExpired:kill(p)
    script.write_text(source)
    p=spawn('enabled');out,err=p.communicate(timeout=2);assert p.returncode==0,(out,err)
    (r/'etc/rc.d/S99demo').unlink()
    p=spawn('enabled');out,err=p.communicate(timeout=2);assert p.returncode==1,(out,err)
    p=spawn('mutate')
    try:p.communicate(timeout=.5);raise AssertionError('mutation bypassed lock')
    except subprocess.TimeoutExpired:assert not (r/'changed').exists()
    fcntl.flock(lock,fcntl.LOCK_UN);out,err=p.communicate(timeout=2);assert p.returncode==0,(out,err)
    assert (r/'changed').read_text()=='changed\n'
print('PASS: baseline query blocked; enabled/disabled queries returned under held lock; mutation still serialized')
