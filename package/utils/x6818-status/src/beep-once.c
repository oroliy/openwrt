// SPDX-License-Identifier: GPL-2.0-only
/* Emit exactly one short SND_BELL pulse on the x6818 GPIO beeper. */

#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int open_beeper(void)
{
	char path[sizeof("/dev/input/event255")];
	char name[128];
	int fd;
	int event;

	for (event = 0; event < 256; event++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", event);
		fd = open(path, O_WRONLY | O_CLOEXEC);
		if (fd < 0)
			continue;
		memset(name, 0, sizeof(name));
		if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0 &&
		    !strcmp(name, "beeper"))
			return fd;
		close(fd);
	}

	return -1;
}

static int send_bell(int fd, int value)
{
	struct input_event event = { 0 };

	event.type = EV_SND;
	event.code = SND_BELL;
	event.value = value;
	return write(fd, &event, sizeof(event)) == (ssize_t)sizeof(event) ? 0 : -1;
}

int main(void)
{
	int fd = open_beeper();

	if (fd < 0)
		return errno ? 1 : 2;
	if (send_bell(fd, 1) < 0) {
		close(fd);
		return 1;
	}
	/* Keep the GPIO asserted long enough to be audible on either buzzer. */
	usleep(120000);
	if (send_bell(fd, 0) < 0) {
		close(fd);
		return 1;
	}
	close(fd);
	return 0;
}
