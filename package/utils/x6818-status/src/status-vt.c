// SPDX-License-Identifier: GPL-2.0-only
/* Supervise LCD4Linux on a dedicated VT, leaving tty1 and serial for logs. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <linux/vt.h>
#include <linux/tiocl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static volatile sig_atomic_t child_pid;

static void stop(int signo)
{
	stopping = signo;
	if (child_pid > 0)
		kill(child_pid, signo);
}

int main(void)
{
	struct vt_stat vt;
	struct winsize size;
	struct termios saved;
	struct sigaction action = { .sa_handler = stop };
	sigset_t blocked, oldmask;
	int lock, tty, status = 0, result = EXIT_FAILURE;
	int previous_redirect;
	unsigned char redirect[2] = { TIOCL_GETKMSGREDIRECT, 0 };
	pid_t child, waited;

	lock = open("/var/run/x6818-status.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB) < 0) {
		perror("x6818-status lock");
		return EXIT_FAILURE;
	}
	tty = open("/dev/tty2", O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (tty < 0 || ioctl(tty, VT_GETSTATE, &vt) < 0 ||
	    ioctl(tty, TIOCGWINSZ, &size) < 0 || tcgetattr(tty, &saved) < 0) {
		perror("x6818-status terminal");
		return EXIT_FAILURE;
	}
	/* Curses allocates an 80x24 window including its border. */
	if (size.ws_col < 80 || size.ws_row < 24) {
		fprintf(stderr, "x6818-status: tty2 must be at least 80x24 (got %ux%u)\n",
			size.ws_col, size.ws_row);
		return EXIT_FAILURE;
	}
	if (ioctl(tty, TIOCLINUX, redirect) < 0) {
		perror("x6818-status get printk VT");
		return EXIT_FAILURE;
	}
	previous_redirect = redirect[0];
	sigemptyset(&action.sa_mask);
	sigaction(SIGTERM, &action, NULL);
	sigaction(SIGINT, &action, NULL);
	sigaction(SIGHUP, &action, NULL);
	sigemptyset(&blocked);
	sigaddset(&blocked, SIGTERM);
	sigaddset(&blocked, SIGINT);
	sigaddset(&blocked, SIGHUP);
	sigprocmask(SIG_BLOCK, &blocked, &oldmask);
	redirect[0] = TIOCL_SETKMSGREDIRECT;
	redirect[1] = 1;
	if (ioctl(tty, TIOCLINUX, redirect) < 0) {
		perror("x6818-status set printk VT");
		goto restore;
	}
	if (ioctl(tty, VT_ACTIVATE, 2) < 0 || ioctl(tty, VT_WAITACTIVE, 2) < 0) {
		perror("x6818-status activate");
		goto restore;
	}
	child = fork();
	if (child < 0) {
		perror("x6818-status fork");
		goto restore;
	}
	if (!child) {
		signal(SIGTERM, SIG_DFL);
		signal(SIGINT, SIG_DFL);
		signal(SIGHUP, SIG_DFL);
		sigprocmask(SIG_SETMASK, &oldmask, NULL);
		if (setsid() < 0 || ioctl(tty, TIOCSCTTY, 0) < 0 ||
		    dup2(tty, STDIN_FILENO) < 0 || dup2(tty, STDOUT_FILENO) < 0)
			_exit(126);
		/* stderr stays with procd; diagnostics remain accessible remotely. */
		setenv("TERM", "linux", 1);
		unsetenv("LINES");
		unsetenv("COLUMNS");
		execl("/usr/bin/lcd4linux", "lcd4linux", "-F", "-q", "-f",
		      "/etc/x6818-status.conf", (char *)NULL);
		perror("lcd4linux exec");
		_exit(127);
	}
	child_pid = child;
	sigprocmask(SIG_SETMASK, &oldmask, NULL);
	for (;;) {
		waited = waitpid(child, &status, 0);
		if (waited == child)
			break;
		if (waited < 0 && errno != EINTR) {
			perror("x6818-status wait");
			goto restore;
		}
	}
	result = stopping ? EXIT_SUCCESS :
		(WIFEXITED(status) ? WEXITSTATUS(status) : EXIT_FAILURE);
restore:
	sigprocmask(SIG_BLOCK, &blocked, NULL);
	child_pid = 0;
	tcsetattr(tty, TCSANOW, &saved);
	/* Reset rendition and show the cursor, even after an app crash. */
	if (write(tty, "\033[0m\033[?25h", sizeof("\033[0m\033[?25h") - 1) < 0)
		perror("x6818-status cursor");
	if (ioctl(tty, VT_ACTIVATE, vt.v_active) < 0)
		perror("x6818-status restore");
	else if (ioctl(tty, VT_WAITACTIVE, vt.v_active) < 0)
		perror("x6818-status wait restore");
	redirect[0] = TIOCL_SETKMSGREDIRECT;
	redirect[1] = previous_redirect;
	if (ioctl(tty, TIOCLINUX, redirect) < 0)
		perror("x6818-status restore printk VT");
	close(tty);
	close(lock);
	return result;
}
