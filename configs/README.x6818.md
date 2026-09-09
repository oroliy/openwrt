# x6818 AArch64 product seed

Install and verify the locked feeds first, then copy `x6818_arm64.config` to
an OpenWrt `.config` and run `make defconfig`. Feed installation can refresh
an existing config before all feed packages are registered, dropping selections.
Run `scripts/check-x6818-config.sh configs/x6818_arm64.config .config` afterward.
The seed is deliberately small: Kconfig supplies libraries, LuCI modules,
kernel modules, and other transitive dependencies.  It is a product input,
not a generated `.config` and not a copy of the arm64 kernel configuration.

## Direct product choices

- `nexell/s5p6818_arm64`, device `nexell_x6818_arm64`: selects the x6818
  AArch64 target and its target image recipe.
- `CONFIG_TARGET_ROOTFS_INITRAMFS`, `EXT4FS`, and `SQUASHFS`: retain the
  initramfs artifact and both filesystem families.  The target image recipe
  combines each filesystem with SD and eMMC firmware channels, yielding four
  disk-image combinations.  The `64 MiB` kernel and `7360 MiB` rootfs values
  are inherited from the original product configuration, not a claim that
  they fit every medium.  ext4 uses 4 KiB blocks, journaling, and zero
  reserved percentage.
- `luci`, `luci-app-cloudflared`, `luci-app-tailscale-community`, `tailscale`,
  `cloudflared`, and `htop`: user-facing management and diagnostics selected
  in both the product configuration and its backup.
- `collectd` with CPU, interface, iwinfo, load, memory, network, and rrdtool
  plugins: the explicitly selected monitoring set.
- `fstools`, `e2fsprogs`, `resize2fs`, `fdisk`, `mount-utils`, `lsblk`, and
  `uboot-envtools`: persistence, ext4 expansion, partition inspection, and
  boot-environment tooling selected for the storage work.

## Capacity and storage boundary

For the current image recipe, the minimum data area before any metadata or
trailing alignment is `32 MiB` reserved prefix plus `64 MiB`
boot plus `7296 MiB` rootfs.  With ptgen's measured 128 MiB rootfs start,
the partition end is `7424 MiB` (`0x1d0000000` bytes), leaving a planned
32 MiB tail before the measured board capacity of `7456 MiB`
(`0x1d2000000` bytes / `0xe90000` 512-byte sectors).  This tail is only a
capacity budget; image metadata and final padding still need validation from
generated images.  An "8 GB" medium must be checked for its real usable
sector count; its nominal label is not a capacity guarantee.  This seed does
not claim that the layout or new-disk images have passed acceptance.

`resize2fs` expands an ext4 filesystem only.  It does not expand a partition;
partition growth and filesystem growth remain separate, ordered operations
that require independent validation by the T4 tests.

## Deliberately omitted

The original `.config` contains a large closure of LuCI libraries, libc,
network services, kernel modules, and host/build selections.  Those are
transitive or target defaults and are intentionally not copied into this
seed.  Optional diagnostics and services seen in the backup (for example
`trace-cmd`, PCI/USB inventory tools, `strace`, PPP/WireGuard extras, and
additional LuCI applications) remain opt-in until separately justified.

No `USE_SOURCE_DIR`, sibling worktree, temporary build path, package source
URL, account, password, key, or token is included.  The BL2/TF-A/U-Boot
development source override remains an explicit build-time gate; it is not a
formal product seed input until the sources have a published immutable URL,
commit, and hash.

The seed does not claim that image construction, persistence across reboot,
firmware download, or board acceptance has passed.  Those remain the T6/T7
gates in `docs/plans/2026-09-08-x6818-product-next-steps.md`.
