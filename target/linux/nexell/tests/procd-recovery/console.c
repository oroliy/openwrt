#define _GNU_SOURCE
#include <assert.h>
#include <pty.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <libubox/uloop.h>
static int test_open(const char *,int,...);
static int test_execl(const char *,const char *,...);
#define main upgraded_main
#define open test_open
#define execl test_execl
#include "upgraded/upgraded.c"
#undef main
#undef open
#undef execl
static char slave_name[128];
static int master, child_ok;
static struct uloop_timeout finish;
static int test_open(const char *file,int flags,...) { return open(!strcmp(file,"/dev/console") ? slave_name : file,flags); }
static int test_execl(const char *file,const char *arg,...) {
 if(!isatty(0)||!isatty(1)||!isatty(2)||tcgetsid(0)!=getpid()||getsid(0)!=getpid()) _exit(70);
 if(write(1,"RECOVERY_PTY_OK\n",16)!=16) _exit(71);
 _exit(0);
}
void watchdog_init(int n) { }
static void finish_cb(struct uloop_timeout *t) { uloop_end(); }
int main(void) {
 int slave; assert(openpty(&master,&slave,slave_name,NULL,NULL)==0); close(slave);
 assert(uloop_init()==0); upgrade_proc_cb(&upgrade_proc,256); assert(recovery_proc.pid>0);
 finish.cb=finish_cb; uloop_timeout_set(&finish,100); uloop_run();
 char buf[128]; int n=read(master,buf,sizeof(buf)-1); assert(n>0); buf[n]=0; child_ok=strstr(buf,"RECOVERY_PTY_OK")!=NULL; assert(child_ok);
 int status; assert(waitpid(recovery_proc.pid,&status,WNOHANG)==-1 && errno==ECHILD); assert(upgrade_status!=0);
 close(master); uloop_done(); puts("PASS: recovery child owns PTY session; stdio0/1/2 are controlling TTY; shell exit preserves failure state"); return 0;
}
