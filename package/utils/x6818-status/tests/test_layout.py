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
import tempfile
import time

binary, config = map(os.path.abspath, sys.argv[1:])
temporary = tempfile.TemporaryDirectory()
temperature = os.path.join(temporary.name, 'temperature')
with open(temperature, 'w') as file:
    file.write('0.0 C\n52.0 C\n')
addresses = os.path.join(temporary.name, 'addresses')
with open(addresses, 'w') as file:
    file.write('Local addresses: 3  Page 1/1\nlo  IPv4  127.0.0.1/8\nbr-lan  IPv4  10.1.1.118/24\nbr-lan  IPv6  2001:db8::118/64\n\n\n\n\n\n')
with open(config) as file:
    layout = file.read().replace('/var/run/x6818-temperature', temperature).replace('/var/run/x6818-addresses', addresses)
config = os.path.join(temporary.name, 'layout.conf')
with open(config, 'w') as file:
    file.write(layout)
os.chmod(config, 0o600)
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
    text = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", bytes(data)).replace(b'\r', b' ')
    for label in (b"OpenWrt", b"Uptime:", b"CPU", b"Memory", b"Local addresses:", b"127.0.0.1/8", b"10.1.1.118/24", b"2001:db8::118/64",
                  b"Ethernet", b"Rootfs", b"TMU0", b"TMU1",
                  b"0.0 C", b"52.0 C"):
        assert label in text, f"missing widget: {label!r}"
    assert all(a < b for a, b in zip(sizes, sizes[1:])), "widgets did not refresh"
    assert not re.search(rb"unknown function|syntax error|parse error|failed", text, re.I), text
    # Sensor service stopped/disappeared: refresh must display N/A.
    os.unlink(temperature)
    data.clear()
    until = time.monotonic() + 3
    while time.monotonic() < until:
        if select.select([master], [], [], 0.1)[0]:
            data.extend(os.read(master, 65536))
    assert b'N/A' in data, 'missing sensor did not render N/A'
    process.send_signal(signal.SIGTERM)
    process.wait(timeout=3)
    assert process.returncode == 0, f"unclean termination: {process.returncode}"
    print(f"PASS: widgets rendered, four refresh samples {sizes}, SIGTERM exit 0")
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    temporary.cleanup()
