#!/usr/bin/env python3
"""Exercise patched upgraded.c without touching devices, root or reboot.

Requires the existing procd archive and host libubox from an OpenWrt build.
Child execs/console open are intercepted; the event-loop test uses real fork,
SIGCHLD reaping and libubox timeout dispatch.
"""
import io
import pathlib
import shutil
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[4]
FIXTURES = pathlib.Path(__file__).resolve().parent / "procd-recovery"
archive = next((ROOT / "dl").glob("procd-2026.03.13*58eb263d*.tar.zst"))
with tempfile.TemporaryDirectory(prefix="nexell-procd-test-") as tmp:
    root = pathlib.Path(tmp)
    (root / "upgraded").mkdir()
    with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(["zstd", "-dc", str(archive)]))) as tar:
        for name in ("upgraded/upgraded.c", "upgraded/CMakeLists.txt", "watchdog.h"):
            entry = next(m for m in tar.getmembers() if m.name.endswith("/" + name))
            (root / name).write_bytes(tar.extractfile(entry).read())
    subprocess.run(["patch", "-p1", "-i", str(ROOT / "package/system/procd/patches/010-nexell-upgrade-failure-recovery.patch")], cwd=root, check=True)
    host = ROOT / "staging_dir/host"
    common = ["cc", "-std=gnu99", "-Wall", "-Werror", "-Wno-unused-parameter", "-I" + str(host / "include")]
    # Unscoped targets must still compile without the feature macro.
    subprocess.run(common + ["-c", str(root / "upgraded/upgraded.c"), "-o", str(root / "unscoped.o")], check=True)
    for name in ("control-flow", "event-loop", "console"):
        shutil.copyfile(FIXTURES / (name + ".c"), root / (name + ".c"))
        command = common + ["-DUPGRADE_FAILURE_RECOVERY", str(root / (name + ".c"))]
        if name in ("event-loop", "console"):
            command += [str(host / "lib/libubox.a")]
        if name == "console":
            command += ["-lutil"]
        command += ["-o", str(root / name)]
        subprocess.run(command, check=True)
        subprocess.run([str(root / name)], check=True, timeout=5)
