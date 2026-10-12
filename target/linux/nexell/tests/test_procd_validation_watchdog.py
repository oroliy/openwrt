#!/usr/bin/env python3
"""Exercise the actual patched procd JSON reader with a delayed validator."""
from pathlib import Path
import io, subprocess, tarfile, tempfile
ROOT=Path(__file__).resolve().parents[4]
archive=next((ROOT/'dl').glob('procd-2026.03.13*58eb263d*.tar.zst'))
with tempfile.TemporaryDirectory() as td:
    t=Path(td)
    with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['zstd','-dc',str(archive)]))) as tar:
        entry=next(m for m in tar.getmembers() if m.name.endswith('/system.c'))
        original=tar.extractfile(entry).read().decode()
    (t/'system.c').write_text(original)
    subprocess.run(['patch','-p1','-i',str(ROOT/'package/system/procd/patches/013-validation-watchdog.patch')],cwd=t,check=True,stdout=subprocess.DEVNULL)
    source=(t/'system.c').read_text()
    enum=source[source.index('enum vjson_state {'):source.index('};',source.index('enum vjson_state {'))+2]
    code=source[source.index('static enum vjson_state vjson_error'):source.index('/**\n * validate_firmware_image_call')]
    pre='''#include <json-c/json.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/wait.h>
static int b, pings;
static json_object *result;
static void blobmsg_add_object(void *unused,json_object *o) {(void)unused;result=json_object_get(o);}
static void watchdog_ping(void) {pings++;alarm(2);}
static void interrupted(int sig) {(void)sig;}
'''
    main='''
int main(int argc,char **argv) {
 int fd[2]; char *err=NULL; pipe(fd);
 struct sigaction sa={.sa_handler=interrupted};sigaction(SIGUSR1,&sa,NULL);
 pid_t pid=fork();if(!pid) {close(fd[0]);if(!strcmp(argv[1],"slow")){sleep(1);kill(getppid(),SIGUSR1);sleep(3);}
 if(!strcmp(argv[1],"fragment")){write(fd[1],"{\\\"valid\\\":",9);sleep(2);write(fd[1],"true}",5);}
 else if(!strcmp(argv[1],"invalid"))write(fd[1],"oops",4);
 else if(!strcmp(argv[1],"incomplete"))write(fd[1],"{",1);
 else if(!strcmp(argv[1],"array"))write(fd[1],"[]",2);
 else if(strcmp(argv[1],"empty"))write(fd[1],"{\\\"valid\\\":false}",15);
 close(fd[1]);_exit(0);}
 close(fd[1]);if(!strcmp(argv[1],"badfd"))close(fd[0]);alarm(2);int r=vjson_parse(fd[0],&err);alarm(0);close(fd[0]);waitpid(pid,NULL,0);
 int good=!strcmp(argv[1],"slow")||!strcmp(argv[1],"fragment");
 if(good && r!=VJSON_SUCCESS)return 1;
 if(!good && r==VJSON_SUCCESS)return 2;
 if(!strcmp(argv[1],"slow") && (pings<4 || json_object_get_boolean(json_object_object_get(result,"valid"))))return 3;
 if(result)json_object_put(result);
 printf("%s state=%d pings=%d\\n",argv[1],r,pings);return 0;
}
'''
    (t/'test.c').write_text(pre+enum+code+main)
    subprocess.run(['cc','-Wall','-Wextra','-Wno-unused-parameter','-I'+str(ROOT/'staging_dir/host/include'),str(t/'test.c'),str(ROOT/'staging_dir/host/lib/libjson-c.a'),'-lm','-o',str(t/'test')],check=True)
    for case in ('slow','fragment','invalid','incomplete','array','empty','badfd'):
        subprocess.run([str(t/'test'),case],check=True,timeout=8)
    oldcode=original[original.index('static enum vjson_state vjson_error'):original.index('/**\n * validate_firmware_image_call')]
    (t/'old.c').write_text(pre+enum+oldcode+main)
    subprocess.run(['cc','-I'+str(ROOT/'staging_dir/host/include'),str(t/'old.c'),str(ROOT/'staging_dir/host/lib/libjson-c.a'),'-lm','-o',str(t/'old')],check=True)
    baseline=subprocess.run([str(t/'old'),'slow'],timeout=8)
    assert baseline.returncode==-14,baseline.returncode
    print('baseline slow reader hit simulated watchdog; fixed reader survived')
