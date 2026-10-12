// SPDX-License-Identifier: GPL-2.0-only
/* Publish fresh TMU readings for LCD4Linux without forking on each refresh. */
#define _POSIX_C_SOURCE 200809L
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;

static void stop(int sig)
{
	(void)sig;
	stopping = 1;
}

static int read_line(const char *root, const char *zone, const char *file,
		     char *buf, size_t size)
{
	char path[PATH_MAX];
	FILE *fp;
	int n = snprintf(path, sizeof(path), "%s/%s/%s", root, zone, file);

	if (n < 0 || (size_t)n >= sizeof(path))
		return -1;
	fp = fopen(path, "r");
	if (!fp)
		return -1;
	if (!fgets(buf, size, fp)) {
		fclose(fp);
		return -1;
	}
	fclose(fp);
	buf[strcspn(buf, "\r\n")] = '\0';
	return 0;
}

static void sample(const char *root, char values[2][32])
{
	struct dirent *entry;
	DIR *dir;
	int i;

	/* Reset each sample so disappeared/failed sensors cannot leave stale data. */
	for (i = 0; i < 2; i++)
		strcpy(values[i], "N/A");
	dir = opendir(root);
	if (!dir)
		return;
	while ((entry = readdir(dir))) {
		char type[64], buf[64], *end;
		long temp;

		if (strncmp(entry->d_name, "thermal_zone", 12) ||
		    read_line(root, entry->d_name, "type", type, sizeof(type)))
			continue;
		if (!strcmp(type, "soc0-thermal"))
			i = 0;
		else if (!strcmp(type, "soc1-thermal"))
			i = 1;
		else
			continue;
		if (read_line(root, entry->d_name, "temp", buf, sizeof(buf)))
			continue;
		errno = 0;
		temp = strtol(buf, &end, 10);
		if (errno || end == buf || *end || temp < -40000 || temp > 150000)
			continue;
		snprintf(values[i], 32, "%.1f C", temp / 1000.0);
	}
	closedir(dir);
}

static int publish(const char *path, char values[2][32])
{
	char temporary[PATH_MAX];
	FILE *fp;
	int fd, n, ret = 0;

	n = snprintf(temporary, sizeof(temporary), "%s.XXXXXX", path);
	if (n < 0 || (size_t)n >= sizeof(temporary))
		return -1;
	fd = mkstemp(temporary);
	if (fd < 0)
		return -1;
	fp = fdopen(fd, "w");
	if (!fp) {
		close(fd);
		unlink(temporary);
		return -1;
	}
	if (fprintf(fp, "%s\n%s\n", values[0], values[1]) < 0)
		ret = -1;
	if (fclose(fp))
		ret = -1;
	if (!ret && rename(temporary, path))
		ret = -1;
	if (ret)
		unlink(temporary);
	return ret;
}

int main(int argc, char **argv)
{
	const char *root = "/sys/class/thermal";
	const char *output = "/var/run/x6818-temperature";
	struct sigaction action = { .sa_handler = stop };
	int once = 0, opt, ret = EXIT_SUCCESS;

	while ((opt = getopt(argc, argv, "1r:o:")) != -1) {
		switch (opt) {
		case '1': once = 1; break;
		case 'r': root = optarg; break;
		case 'o': output = optarg; break;
		default: return EXIT_FAILURE;
		}
	}
	if (optind != argc)
		return EXIT_FAILURE;
	sigemptyset(&action.sa_mask);
	sigaction(SIGTERM, &action, NULL);
	sigaction(SIGINT, &action, NULL);
	do {
		char values[2][32];
		struct timespec delay = { .tv_sec = 2 };

		sample(root, values);
		if (publish(output, values)) {
			perror("x6818-temperature");
			ret = EXIT_FAILURE;
			break;
		}
		if (once)
			return EXIT_SUCCESS;
		while (!stopping && nanosleep(&delay, &delay) && errno == EINTR)
			;
	} while (!stopping);
	/* Clear readings on orderly stop; procd restarts failed instances. */
	unlink(output);
	return ret;
}
