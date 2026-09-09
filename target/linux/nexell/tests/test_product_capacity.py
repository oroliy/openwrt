#!/usr/bin/env python3
"""Check the x6818 seed against the measured board capacity and ptgen."""
import pathlib
import os
import re
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[4]
SEED = ROOT / "configs/x6818_arm64.config"
PTGEN = pathlib.Path(os.environ.get("X6818_PTGEN", str(ROOT / "staging_dir/host/bin/ptgen")))
BOARD_SECTORS = 15269888  # measured /sys/block/mmcblk0/size
SECTOR = 512
TAIL = 32 * 1024 * 1024


def seed_mib(symbol):
    text = SEED.read_text()
    match = re.search(r"^" + re.escape(symbol) + r"=(\d+)$", text, re.M)
    if not match:
        raise AssertionError(f"seed has no {symbol}")
    return int(match.group(1))


def ptgen_root_end(rootfs_mib_value, bootfs_mib_value=None):
    if bootfs_mib_value is None:
        bootfs_mib_value = seed_mib("CONFIG_TARGET_KERNEL_PARTSIZE")
    with tempfile.NamedTemporaryFile() as image:
        proc = subprocess.run(
            [str(PTGEN), "-o", image.name, "-h16", "-s63", "-l32768",
             "-tc", f"-p{bootfs_mib_value}M", "-t83", f"-p{rootfs_mib_value}M"],
            check=True, text=True, capture_output=True,
        )
    numeric = [int(line) for line in proc.stdout.splitlines()]
    if len(numeric) != 4:
        raise AssertionError(f"unexpected ptgen output: {proc.stdout!r}")
    root_start, root_size = numeric[-2:]
    return root_start + root_size


class ProductCapacity(unittest.TestCase):
    def test_seed_fits_measured_capacity_with_tail(self):
        rootfs = seed_mib("CONFIG_TARGET_ROOTFS_PARTSIZE")
        self.assertEqual(rootfs, 7296)
        capacity = BOARD_SECTORS * SECTOR
        self.assertEqual(ptgen_root_end(rootfs), 7424 * 1024 * 1024)
        self.assertLessEqual(ptgen_root_end(rootfs), capacity - TAIL)

    def test_previous_7360_size_does_not_fit(self):
        capacity = BOARD_SECTORS * SECTOR
        self.assertEqual(ptgen_root_end(7360), capacity + 32 * 1024 * 1024)

    def test_larger_boot_partition_is_not_ignored(self):
        self.assertGreater(ptgen_root_end(7296, 128), BOARD_SECTORS * SECTOR)


if __name__ == "__main__":
    unittest.main()
