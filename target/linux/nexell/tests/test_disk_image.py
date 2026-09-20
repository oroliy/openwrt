#!/usr/bin/env python3
"""Offline tests for the x6818 partition-image wrapper."""

import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[4]
SCRIPT = ROOT / "target/linux/nexell/image/gen_nexell_disk_img.sh"


class DiskImageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.work = Path(self.tmp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        # Deterministic stub for negative cases; a separate test uses ptgen.
        (self.bin / "ptgen").write_text(
            "#!/usr/bin/env python3\n"
            "import pathlib, sys\n"
            "out = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])\n"
            "sizes = [int(x[:-1]) * 1024 * 1024 for x in sys.argv if x.endswith('M')]\n"
            "boot = 65536 * 512\n"
            "root = boot + sizes[0]\n"
            "out.parent.mkdir(parents=True, exist_ok=True)\n"
            "out.write_bytes(bytes(root + sizes[1]))\n"
            "print(boot, sizes[0], root, sizes[1])\n"
        )
        (self.bin / "ptgen").chmod(0o755)
        self.boot = self.work / "boot.fs"
        self.rootfs = self.work / "root.fs"
        self.boot.write_bytes(b"BOOT" * 128)
        self.rootfs.write_bytes(b"ROOT" * 128)

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def nexell_crc(data, polynomial):
        crc = 0
        for byte in data:
            crc ^= byte
            for _ in range(8):
                crc = ((crc >> 1) ^ polynomial) if crc & 1 else crc >> 1
        return crc & 0xffffffff

    def firmware(self, channel=0, magic=True, size=4096, bad_crc=False):
        if size >= 512:
            size = max(size, 0x20800)
        data = bytearray(size)
        struct.pack_into("<I", data, 0x50, channel)
        bl2_size = 0x400
        struct.pack_into("<I", data, 0x44, bl2_size)
        struct.pack_into("<I", data, 0x40, 0x10200)
        struct.pack_into("<II", data, 0x48, 0xffff0000, 0xffff0000)
        data[0x57] = 3
        if magic and size >= 512:
            struct.pack_into("<I", data, 0x1FC, 0x4849534E)
            for offset in (0x10000, 0x20000):
                struct.pack_into("<I", data, offset + 0x1FC, 0x4849534E)
                struct.pack_into("<I", data, offset + 0x50, 4)
                if offset == 0x10000:
                    struct.pack_into("<QQ", data, offset + 0x58,
                                     0x7FE7FC00, 0x7FE80000)
                    struct.pack_into("<Q", data, offset + 0xA0, 0x20200)
                else:
                    struct.pack_into("<QQ", data, offset + 0x58,
                                     0x43BFFC00, 0x43C00000)
                    struct.pack_into("<Q", data, offset + 0xA0, 0)
                payload = bytes(((offset >> 16) & 0xff,)) * 4
                data[offset + 0x400:offset + 0x404] = payload
                struct.pack_into("<I", data, offset + 0x54,
                                 self.nexell_crc(payload, 0xEDB88320))
            struct.pack_into("<I", data, 0x58,
                             self.nexell_crc(bytes(0x200) +
                                             bytes(data[0x200:bl2_size]),
                                             0x04C11DB7))
            if bad_crc:
                data[0x200] ^= 1
        path = self.work / f"firmware-{channel}.img"
        path.write_bytes(data)
        return path

    def invoke(self, firmware, channel, bootfs=None, rootfs=None,
               ptgen_dir=None, boot_size="1", root_size="1", name=None):
        output = self.work / f"image-{name or channel}.img"
        prefix = str(ptgen_dir or self.bin)
        env = dict(os.environ, PATH=f"{prefix}:{os.environ['PATH']}")
        return subprocess.run(
            [str(SCRIPT), str(output), str(bootfs or self.boot),
             str(rootfs or self.rootfs), boot_size, root_size, str(channel),
             str(firmware)], env=env, text=True, capture_output=True
        )

    def test_sd_and_emmc_channels_are_distinct_and_placed(self):
        for channel in (0, 2):
            result = self.invoke(self.firmware(channel), channel)
            self.assertEqual(result.returncode, 0, result.stderr)
            image = (self.work / f"image-{channel}.img").read_bytes()
            self.assertEqual(struct.unpack_from("<I", image, 0x1FC + 512)[0],
                             0x4849534E)
            self.assertEqual(struct.unpack_from("<I", image, 0x50 + 512)[0],
                             channel)

    def test_missing_and_truncated_firmware_fail_closed(self):
        missing = self.work / "missing.img"
        result = self.invoke(missing, 0)
        self.assertNotEqual(result.returncode, 0)
        short = self.firmware(0, size=511)
        result = self.invoke(short, 0)
        self.assertNotEqual(result.returncode, 0)

    def test_bad_magic_and_channel_fail_closed(self):
        result = self.invoke(self.firmware(0, magic=False), 0)
        self.assertNotEqual(result.returncode, 0)
        result = self.invoke(self.firmware(2), 0)
        self.assertNotEqual(result.returncode, 0)

    def test_boot_and_rootfs_capacity_are_checked(self):
        too_big_boot = self.work / "too-big-boot"
        too_big_boot.write_bytes(b"x" * (1024 * 1024 + 1))
        result = self.invoke(self.firmware(0), 0, bootfs=too_big_boot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("bootfs exceeds partition 1 capacity", result.stderr)
        too_big_root = self.work / "too-big-root"
        too_big_root.write_bytes(b"x" * (1024 * 1024 + 1))
        result = self.invoke(self.firmware(0), 0, rootfs=too_big_root,
                             name="too-big-root")
        self.assertNotEqual(result.returncode, 0)

        self.assertIn("rootfs exceeds partition 2 capacity", result.stderr)

    def test_ptgen_failure_is_fatal(self):
        bad = self.work / "bad-bin"
        bad.mkdir()
        (bad / "ptgen").write_text("#!/bin/sh\necho '33554432 1048576 34603008 1048576'\nexit 7\n")
        (bad / "ptgen").chmod(0o755)
        result = self.invoke(self.firmware(0), 0, ptgen_dir=bad, name="ptgen-fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ptgen failed", result.stderr)

    def test_firmware_crc_is_checked(self):
        for offset, stage in ((0x200, "BL2"), (0x10400, "BL31"),
                              (0x20400, "BL33")):
            firmware = self.firmware(0)
            data = bytearray(firmware.read_bytes())
            data[offset] ^= 1
            firmware.write_bytes(data)
            result = self.invoke(firmware, 0, name=f"bad-crc-{stage}")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f"{stage} payload CRC mismatch", result.stderr)

    def test_firmware_header_contracts_are_checked(self):
        mutations = (
            (0x40, 0x10300, "BL2 load/entry/boot-device contract mismatch"),
            (0x10000 + 0x60, 0x7FE90000,
             "secure image load/entry/next-stage contract mismatch"),
            (0x20000 + 0x50, 5, "BL33 payload is truncated"),
        )
        for index, value, message in mutations:
            firmware = self.firmware(0)
            data = bytearray(firmware.read_bytes())
            struct.pack_into("<I", data, index, value)
            firmware.write_bytes(data)
            result = self.invoke(firmware, 0, name=f"header-{index:x}")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)

    def test_ptgen_rejects_bad_partition_layout(self):
        for fields, name, message in (
            ("33554433 1048576 34603008 1048576", "unaligned", "unaligned partition fields"),
            ("8388608 1048576 17825792 1048576", "early", "invalid partition start or size"),
            ("33554432 1048576 34078720 1048576", "overlap", "overlapping partitions"),
        ):
            bad = self.work / f"{name}-bin"
            bad.mkdir()
            (bad / "ptgen").write_text(
                f"#!/bin/sh\nprintf '%s\\n' '{fields}'\n")
            (bad / "ptgen").chmod(0o755)
            result = self.invoke(self.firmware(0), 0, ptgen_dir=bad,
                                 name=f"layout-{name}")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)

    def test_real_ptgen_writes_32mib_aligned_mbr(self):
        host_bin = Path(os.environ.get(
            "OPENWRT_HOST_BIN",
            "/home/liy/workdir/port/openwrt/staging_dir/host/bin"))
        if not (host_bin / "ptgen").is_file():
            self.skipTest("OpenWrt host ptgen is unavailable")
        result = self.invoke(self.firmware(0), 0, ptgen_dir=host_bin,
                             boot_size="64", root_size="256")
        self.assertEqual(result.returncode, 0, result.stderr)
        image = (self.work / "image-0.img").read_bytes()
        self.assertEqual(image[510:512], b"\x55\xaa")
        self.assertEqual(struct.unpack_from("<I", image, 446 + 8)[0], 0x10000)
        self.assertEqual(struct.unpack_from("<I", image, 462 + 8)[0], 0x40000)
        self.assertEqual(len(image), (0x40000 + 256 * 2048) * 512)

    def test_squashfs_rootfs_gets_preformatted_overlay(self):
        rootfs = self.work / "root.squashfs"
        rootfs_data = bytearray(2 * 1024 * 1024)
        rootfs_data[0:4] = b"hsqs"
        struct.pack_into("<Q", rootfs_data, 40, len(rootfs_data))
        rootfs.write_bytes(rootfs_data)

        result = self.invoke(self.firmware(0), 0, rootfs=rootfs,
                             root_size="64", name="preformatted")
        self.assertEqual(result.returncode, 0, result.stderr)
        image = (self.work / "image-preformatted.img").read_bytes()
        # The default ptgen stub returns the partition fields on stdout but
        # deliberately does not write an MBR; its p2 start is boot+root.
        root_start = (65536 + 2048) * 512
        overlay_start = root_start + len(rootfs_data)
        self.assertEqual(struct.unpack_from("<H", image,
                                            overlay_start + 0x438)[0],
                         0xEF53)


if __name__ == "__main__":
    unittest.main()
