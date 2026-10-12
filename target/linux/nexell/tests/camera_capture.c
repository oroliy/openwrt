// SPDX-License-Identifier: GPL-2.0-only
/* Bounded V4L2 MMAP capture check; no persistent writes. */
#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <linux/magic.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/vfs.h>
#include <unistd.h>

static int xioctl(int fd, unsigned long op, void *arg)
{
	int ret;
	do { ret = ioctl(fd, op, arg); } while (ret < 0 && errno == EINTR);
	return ret;
}

/* A whole poisoned row means the driver completed a partial DMA buffer. */
static int first_untouched_row(const unsigned char *data, unsigned stride,
			       unsigned height)
{
	for (unsigned row = 0; row < height; row++) {
		unsigned column;
		for (column = 0; column < stride; column++)
			if (data[row * stride + column] != 0xa5)
				break;
		if (column == stride)
			return row;
	}
	return -1;
}

static uint32_t crc32(const unsigned char *p, size_t size)
{
	uint32_t table[256], crc = ~0U;

	for (unsigned value = 0; value < 256; value++) {
		uint32_t entry = value;
		for (unsigned bit = 0; bit < 8; bit++)
			entry = (entry >> 1) ^ (0xedb88320U & -(entry & 1));
		table[value] = entry;
	}
	while (size--)
		crc = (crc >> 8) ^ table[(crc ^ *p++) & 0xff];
	return ~crc;
}

/* Output is optional and restricted to one new file in the tmpfs /tmp. */
static int save_first_frame(const char *path, const unsigned char *data, size_t size)
{
	struct statfs fs;
	int dir = -1, fd = -1, result = -1;
	size_t offset = 0;

	if (strncmp(path, "/tmp/", 5) || !path[5] || strchr(path + 5, '/') ||
	    !strcmp(path + 5, ".") || !strcmp(path + 5, "..")) {
		errno = EINVAL;
		return -1;
	}
	dir = open("/tmp", O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
	if (dir < 0)
		return -1;
	if (fstatfs(dir, &fs) < 0)
		goto out;
	if ((unsigned long)fs.f_type != TMPFS_MAGIC) {
		errno = EPERM;
		goto out;
	}
	fd = openat(dir, path + 5, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
	if (fd < 0)
		goto out;
	while (offset < size) {
		ssize_t n = write(fd, data + offset, size - offset);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0) {
			if (!n)
				errno = EIO;
			goto out;
		}
		offset += n;
	}
	result = 0;
out:
	if (fd >= 0 && close(fd) < 0 && !result)
		result = -1;
	close(dir);
	return result;
}

int main(int argc, char **argv)
{
	setvbuf(stdout, NULL, _IOLBF, 0);
	const char *node = argc > 1 ? argv[1] : "/dev/video0";
	const char *output = argc > 2 ? argv[2] : NULL;
	struct v4l2_capability cap;
	struct v4l2_format fmt = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE };
	struct v4l2_requestbuffers req = { .count = 4,
		.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP };
	struct { void *addr; size_t length; } buffers[4] = {0};
	enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	int fd = open(node, O_RDWR | O_NONBLOCK), result = 1, streaming = 0;
	unsigned mapped = 0, last_sequence = 0;
	struct timeval last_time = {0};
	unsigned char *snapshot = NULL;

	if (fd < 0) { perror("open video"); return 1; }
	if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) { perror("QUERYCAP"); goto out; }
	if (strcmp((char *)cap.driver, "s5p6818-capture")) {
		fprintf(stderr, "unexpected driver: %.16s\n", cap.driver); goto out;
	}
	fmt.fmt.pix.width = 1280; fmt.fmt.pix.height = 960;
	fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
	fmt.fmt.pix.field = V4L2_FIELD_NONE;
	if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0) { perror("S_FMT"); goto out; }
	printf("format=%ux%u fourcc=%08x stride=%u size=%u\n", fmt.fmt.pix.width,
		fmt.fmt.pix.height, fmt.fmt.pix.pixelformat, fmt.fmt.pix.bytesperline,
		fmt.fmt.pix.sizeimage);
	if (fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV ||
	    fmt.fmt.pix.sizeimage < fmt.fmt.pix.bytesperline * fmt.fmt.pix.height)
		goto out;
	snapshot = malloc(fmt.fmt.pix.sizeimage);
	if (!snapshot) { perror("allocate frame snapshot"); goto out; }
	if (xioctl(fd, VIDIOC_REQBUFS, &req) < 0) { perror("REQBUFS"); goto out; }
	if (req.count < 2 || req.count > 4) goto out;
	for (unsigned i = 0; i < req.count; i++) {
		struct v4l2_buffer b = { .type = type, .memory = V4L2_MEMORY_MMAP, .index = i };
		if (xioctl(fd, VIDIOC_QUERYBUF, &b) < 0) { perror("QUERYBUF"); goto out; }
		buffers[i].length = b.length;
		if (i == 0 && b.length > fmt.fmt.pix.sizeimage) {
			unsigned char *expanded = realloc(snapshot, b.length);
			if (!expanded) { perror("expand guard snapshot"); goto out; }
			snapshot = expanded;
		}
		buffers[i].addr = mmap(NULL, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, b.m.offset);
		if (buffers[i].addr == MAP_FAILED) { perror("mmap"); goto out; }
		mapped++;
		/* Poison proves DMA modified the capture buffer. */
		memset(buffers[i].addr, 0xa5, b.length);
		if (xioctl(fd, VIDIOC_QBUF, &b) < 0) { perror("QBUF"); goto out; }
	}
	if (xioctl(fd, VIDIOC_STREAMON, &type) < 0) { perror("STREAMON"); goto out; }
	streaming = 1;
	for (unsigned frame = 0; frame < 20; frame++) {
		struct pollfd p = { .fd = fd, .events = POLLIN };
		struct v4l2_buffer b = { .type = type, .memory = V4L2_MEMORY_MMAP };
		int ret = poll(&p, 1, 5000);
		if (ret <= 0 || !(p.revents & POLLIN)) {
			fprintf(stderr, "frame %u poll=%d events=%x\n", frame, ret, p.revents);
			xioctl(fd, VIDIOC_LOG_STATUS, NULL); goto out;
		}
		if (xioctl(fd, VIDIOC_DQBUF, &b) < 0) { perror("DQBUF"); goto out; }
		if (b.index >= mapped || b.bytesused != fmt.fmt.pix.bytesperline * fmt.fmt.pix.height ||
		    b.bytesused > buffers[b.index].length || (b.flags & V4L2_BUF_FLAG_ERROR)) goto out;
		if (frame && ((int32_t)(b.sequence - last_sequence) <= 0 ||
		    b.timestamp.tv_sec < last_time.tv_sec ||
		    (b.timestamp.tv_sec == last_time.tv_sec && b.timestamp.tv_usec <= last_time.tv_usec))) goto out;
		/* Read uncached DMA once, including diagnostic guard space. */
		memcpy(snapshot, buffers[b.index].addr, buffers[b.index].length);
		size_t guard_first = 0, guard_last = 0, guard_changed = 0;
		for (size_t offset = fmt.fmt.pix.sizeimage; offset < buffers[b.index].length; offset++) {
			if (snapshot[offset] != 0xa5) {
				if (!guard_changed) guard_first = offset;
				guard_last = offset;
				guard_changed++;
			}
		}
		if (guard_changed) {
			fprintf(stderr, "DMA overrun: buffer %u size=%u allocation=%zu first=%zu last=%zu changed=%zu\n",
				b.index, b.bytesused, buffers[b.index].length,
				guard_first, guard_last, guard_changed);
			goto out;
		}
		unsigned char *data = snapshot;
		int untouched = first_untouched_row(data, fmt.fmt.pix.bytesperline,
					    fmt.fmt.pix.height);
		if (untouched >= 0) {
			fprintf(stderr, "incomplete DMA: untouched row %d\n", untouched);
			goto out;
		}
		unsigned bins[256] = {0}, distinct = 0;
		for (unsigned j = 0; j < b.bytesused; j += 97) bins[data[j]]++;
		for (unsigned j = 0; j < 256; j++) distinct += !!bins[j];
		printf("%s=%u sequence=%u bytes=%u timestamp=%ld.%06ld crc32=%08x bins=%u\n",
			frame < 4 ? "warmup" : "frame", frame < 4 ? frame : frame - 4, b.sequence, b.bytesused, (long)b.timestamp.tv_sec,
			(long)b.timestamp.tv_usec, crc32(data, b.bytesused), distinct);
		/* Sensor startup frames are discarded; retain all DMA safety checks. */
		if (frame >= 4 && distinct < 4) {
			fprintf(stderr, "constant image after warmup\n");
			goto out;
		}
		if (frame == 4 && output) {
			if (save_first_frame(output, data, b.bytesused) < 0) {
				perror("save first frame to tmpfs"); goto out;
			}
			printf("first-frame=%s bytes=%u crc32=%08x\n", output,
				b.bytesused, crc32(data, b.bytesused));
		}
		last_sequence = b.sequence; last_time = b.timestamp;
		memset(buffers[b.index].addr, 0xa5, buffers[b.index].length);
		if (xioctl(fd, VIDIOC_QBUF, &b) < 0) { perror("requeue"); goto out; }
	}
	result = 0;
out:
	if (streaming && xioctl(fd, VIDIOC_STREAMOFF, &type) < 0) { perror("STREAMOFF"); result = 1; }
	for (unsigned i = 0; i < mapped; i++) munmap(buffers[i].addr, buffers[i].length);
	if (close(fd) < 0) { perror("close video"); result = 1; }
	free(snapshot);
	if (!result)
		puts("PASS: 16 complete nonconstant DMA frames after 4 warmup frames, size/sequence/timestamp checked; visual image quality remains separate; STREAMOFF/close completed");
	return result;
}
