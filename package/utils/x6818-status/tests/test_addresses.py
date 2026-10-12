#!/usr/bin/env python3
"""Exercise address collection and page refresh through the actual shell script."""
import os, subprocess, tempfile, pathlib, time, signal
src=str(pathlib.Path(__file__).resolve().parents[1] / 'files/x6818-addresses')
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d); fake=p/'ip'; fake.write_text('#!/bin/sh\ncat "$ADDRESS_FIXTURE"\n'); fake.chmod(0o755)
 fixture=p/'fixture'; out=p/'out'; env=dict(os.environ,PATH=d+':'+os.environ['PATH'],ADDRESS_FIXTURE=str(fixture))
 entries=['1: lo inet 127.0.0.1/8 scope host lo','4: br-lan inet 192.168.1.1/24 scope global br-lan','4: br-lan inet 10.1.1.118/24 scope global br-lan','4: br-lan inet6 2001:db8::118/64 scope global']+[f'{i}: tun{i}@eth0 inet 10.0.0.{i}/24 scope global' for i in range(5,12)]
 fixture.write_text('\n'.join(entries)+'\n4: br-lan inet6 2001:db8::bad/64 scope global tentative \\n\n')
 subprocess.run(['sh',src,str(out),'--once'],check=True,env=env)
 rows=out.read_text().splitlines(); assert len(rows)==9 and '11  Page 1/2' in rows[0],rows
 assert '192.168.1.1/24' in rows[2] and '10.1.1.118/24' in rows[3] and '2001:db8::118/64' in rows[4],rows
 process=subprocess.Popen(['sh',src,str(out)],env=env)
 try:
  time.sleep(6.5); rows=out.read_text().splitlines(); assert 'Page 2/2' in rows[0] and 'tun11  IPv4  10.0.0.11/24' in rows,rows
  fixture.write_text(''); time.sleep(2.5); rows=out.read_text().splitlines(); assert '0  Page 1/1' in rows[0] and rows[1]=='unassigned',rows
 finally:
  process.send_signal(signal.SIGTERM);process.wait(timeout=4)
 print('PASS: aliases, IPv6, all interfaces, pagination, address removal, SIGTERM')
