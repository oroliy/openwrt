#!/usr/bin/env python3
"""Exercise actual sampler with reordered, invalid and disappearing sensors."""
import pathlib
import subprocess
import sys
import tempfile
import time

binary = str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    sensors = root / 'thermal'
    sensors.mkdir()
    output = root / 'readings'

    def zone(number, name, value):
        path = sensors / f'thermal_zone{number}'
        path.mkdir(exist_ok=True)
        (path / 'type').write_text(name + '\n')
        (path / 'temp').write_text(value + '\n')
        return path

    def read():
        subprocess.run([binary, '-1', '-r', str(sensors), '-o', str(output)], check=True)
        return output.read_text()

    assert read() == 'N/A\nN/A\n'
    first = zone(9, 'soc0-thermal', '47500')
    second = zone(2, 'soc1-thermal', '52000')
    zone(0, 'unrelated', '99000')
    assert read() == '47.5 C\n52.0 C\n'
    (first / 'temp').write_text('-5500\n')
    (second / 'temp').write_text('0\n')
    assert read() == '-5.5 C\n0.0 C\n'
    for bad in ('garbage', '42000x', '', '999999999999999999999999', '151000', '-41000'):
        (first / 'temp').write_text(bad + '\n')
        assert read() == 'N/A\n0.0 C\n', bad
    (first / 'temp').write_text('60000\n')
    process = subprocess.Popen([binary, '-r', str(sensors), '-o', str(output)])
    try:
        deadline = time.monotonic() + 4
        while output.read_text() != '60.0 C\n0.0 C\n':
            assert time.monotonic() < deadline, 'daemon did not publish'
            time.sleep(.05)
        (first / 'temp').unlink()
        (second / 'temp').write_text('invalid\n')
        deadline = time.monotonic() + 4
        while output.read_text() != 'N/A\nN/A\n':
            assert time.monotonic() < deadline, 'stale sensor reading retained'
            time.sleep(.05)
        process.terminate()
        assert process.wait(timeout=1) == 0
        assert not output.exists(), 'stale data retained on stop'
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    failed = subprocess.run([binary, '-1', '-r', str(sensors),
                             '-o', str(root / 'missing' / 'readings')], capture_output=True)
    assert failed.returncode != 0, 'failed publication reported success'
    assert not list(root.glob('readings.*')), 'temporary files leaked'
print('PASS: discovery, units, missing/invalid readings, refresh, stop and write failure')
