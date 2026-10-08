#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
#include <libubox/uloop.h>
static int test_execvp(const char *, char *const []);
static int test_execl(const char *, const char *, ...);
static int test_open(const char *, int, ...);
#define main upgraded_main
#define execvp test_execvp
#define execl test_execl
#define open test_open
#include "upgraded/upgraded.c"
#undef main
#undef execvp
#undef execl
#undef open
static int pings;
static struct uloop_timeout feed;
static int test_execvp(const char *file, char *const args[]) { assert(!strcmp(file,"/lib/upgrade/stage2")); errno=ENOEXEC; return -1; }
static int test_execl(const char *file, const char *arg, ...) { assert(!strcmp(file,"/bin/ash")); errno=ENOEXEC; return -1; }
static int test_open(const char *file, int flags, ...) { return open(!strcmp(file,"/dev/console") ? "/dev/null" : file, flags); }
static void feed_cb(struct uloop_timeout *t) { pings++; if(pings==20) uloop_end(); else uloop_timeout_set(t,10); }
void watchdog_init(int n) { feed.cb=feed_cb; uloop_timeout_set(&feed,10); }
int main(void) {
 assert(uloop_init()==0); watchdog_init(0); sysupgrade("unused-image", "unused-command");
 assert(pings==20); assert(recovery_proc.pid>0); int st; assert(waitpid(recovery_proc.pid,&st,WNOHANG)==-1 && errno==ECHILD);
 uloop_done(); puts("PASS: real libubox process reaping; failed writer and failed recovery exec; 20 watchdog timer callbacks persisted"); return 0;
}
