#!/usr/bin/env python3
"""Exercise the actual LCD4Linux config in a 128x37 pseudo-terminal."""
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

binary, config = map(os.path.abspath, sys.argv[1:])
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 37, 128, 0, 0))
env = dict(os.environ, TERM="linux")
env.pop("LINES", None)
env.pop("COLUMNS", None)
process = subprocess.Popen([binary, "-F", "-q", "-f", config],
                           stdin=slave, stdout=slave, stderr=slave, env=env)
os.close(slave)
data = bytearray()
sizes = []
try:
    for _ in range(4):
        until = time.monotonic() + 1.1
        while time.monotonic() < until:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    data.extend(os.read(master, 65536))
                except OSError:
                    break
        sizes.append(len(data))
        assert process.poll() is None, f"LCD4Linux exited early: {process.returncode}"
    text = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", bytes(data))
    for label in (b"OpenWrt", b"Uptime:", b"CPU", b"Memory", b"IPv4:",
                  b"Ethernet", b"Rootfs", b"unassigned"):
        assert label in text, f"missing widget: {label!r}"
    assert all(a < b for a, b in zip(sizes, sizes[1:])), "widgets did not refresh"
    assert not re.search(rb"unknown function|syntax error|parse error|failed", text, re.I), text
    process.send_signal(signal.SIGTERM)
    process.wait(timeout=3)
    assert process.returncode == 0, f"unclean termination: {process.returncode}"
    print(f"PASS: widgets rendered, four refresh samples {sizes}, SIGTERM exit 0")
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
