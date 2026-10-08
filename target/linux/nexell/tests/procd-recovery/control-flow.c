#define _GNU_SOURCE
#include <assert.h>
#include <setjmp.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/reboot.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <errno.h>
#include <libubox/uloop.h>
static void test_uloop_end(void);
#define uloop_end test_uloop_end
static pid_t fake_fork(void);
static pid_t fake_waitpid(pid_t, int *, int);
#define fork fake_fork
#define waitpid fake_waitpid
static pid_t fake_getpid(void);
static int fake_open(const char *, int, ...);
static int fake_chroot(const char *);
static int fake_fchdir(int);
static int fake_close(int);
static int fake_reboot(int);
#define getpid fake_getpid
#define open fake_open
#define chroot fake_chroot
#define fchdir fake_fchdir
#define close fake_close
#define reboot fake_reboot
#define main upgraded_main
#include "upgraded/upgraded.c"
#undef main
static int forks, ends, runs, add_failure, timeout_sets, wait_result, wait_status;
static int exercise_main, child_status, reboots;
static jmp_buf held;
static pid_t fake_getpid(void) { return 1; }
static int fake_open(const char *p, int flags, ...) { return 42; }
static int fake_chroot(const char *p) { return 0; }
static int fake_fchdir(int fd) { assert(fd==42); return 0; }
static int fake_close(int fd) { return 0; }
static int fake_reboot(int cmd) { assert(cmd==RB_AUTOBOOT); reboots++; return 0; }
static pid_t fake_fork(void) { forks++; return forks == 1 && add_failure == 2 ? -1 : 123; }
static pid_t fake_waitpid(pid_t pid, int *status, int flags) { assert(flags == WNOHANG); *status=wait_status; return wait_result; }
static void uloop_end(void) { ends++; }
int uloop_process_add(struct uloop_process *p) { return add_failure == 1 && p == &upgrade_proc ? -1 : 0; }
int uloop_run_timeout(int timeout) {
 runs++;
 if(exercise_main && runs==1) upgrade_proc_cb(&upgrade_proc,child_status);
 if(exercise_main && runs==2) longjmp(held,1);
 return 0;
}
int uloop_init(void) { return 0; }
int uloop_timeout_set(struct uloop_timeout *t, int ms) { assert(ms == 1000); timeout_sets++; return 0; }
void watchdog_init(int n) { }
static void reset(void) { forks=ends=runs=timeout_sets=add_failure=exercise_main=reboots=0; upgrade_status=EXIT_FAILURE; recovery_started=0; }
int main(void) {
 reset(); upgrade_proc_cb(&upgrade_proc, 0); assert(ends==1 && forks==0);
 reset(); upgrade_proc_cb(&upgrade_proc, 256); assert(ends==0 && forks==1);
 reset(); upgrade_proc_cb(&upgrade_proc, SIGSEGV); assert(ends==0 && forks==1);
 reset(); recovery_proc_cb(&recovery_proc, 0); assert(ends==0 && forks==0);
 reset(); add_failure=2; sysupgrade("fixture", "fixture"); assert(ends==0 && forks==2 && runs==1);
 reset(); add_failure=1; sysupgrade("fixture", "fixture"); assert(forks==1 && ends==0 && timeout_sets==1 && runs==1);
 wait_result=0; upgrade_poll_cb(&upgrade_poll); assert(timeout_sets==2 && forks==1);
 wait_result=-1; errno=EINTR; upgrade_poll_cb(&upgrade_poll); assert(timeout_sets==3 && forks==1 && ends==0);
 wait_result=123; wait_status=256; upgrade_poll_cb(&upgrade_poll); assert(forks==2 && ends==0);
 reset(); wait_result=-1; errno=ECHILD; upgrade_poll_cb(&upgrade_poll); assert(forks==1 && ends==0 && upgrade_status!=0);
 upgrade_recovery(); assert(forks==1);
 reset(); wait_result=123; wait_status=0; upgrade_poll_cb(&upgrade_poll); assert(ends==1 && forks==0);
 char *args[] = {"upgraded", "fixture", "fixture", NULL};
 reset(); exercise_main=1; child_status=0; assert(upgraded_main(3,args)==0); assert(reboots==1);
 reset(); exercise_main=1; child_status=256;
 if(!setjmp(held)) { upgraded_main(3,args); assert(!"failed upgrade returned"); }
 assert(reboots==0 && runs==2 && upgrade_status==256);
 puts("PASS: full PID1 success reboot and failed-child loop-return guard; all privileged calls intercepted");
 puts("PASS: success, failure, signal, shell exit, writer fork failure, watcher fallback pending/EINTR/ECHILD/failure/success; recovery exactly once");
 return 0;
}
