#!/bin/sh
# Check the reviewed x6818 product seed against a defconfig result.
set -eu

usage() {
	echo "usage: $0 SEED CONFIG" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage
seed=$1
config=$2
[ -r "$seed" ] || { echo "missing seed: $seed" >&2; exit 2; }
[ -r "$config" ] || { echo "missing config: $config" >&2; exit 2; }

fail=0
check_line() {
	line=$1
	if ! grep -Fqx "$line" "$config"; then
		echo "FAIL: missing or changed: $line" >&2
		fail=1
	fi
}

while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in
		CONFIG_*=*) check_line "$line" ;;
	esac
done < "$seed"

check_exact() {
	name=$1
	value=$2
	check_line "${name}=${value}"
}

# Ensure the resolved target is the intended 64-bit AArch64 product.
check_exact CONFIG_ARCH '"aarch64"'
check_exact CONFIG_ARCH_64BIT y
check_exact CONFIG_TARGET_ARCH_PACKAGES '"aarch64_cortex-a53"'

# Firmware/runtime packages must be selected; missing one is a packaging gate.
check_exact CONFIG_PACKAGE_nexell-firmware y
check_exact CONFIG_PACKAGE_u-boot-x6818_arm64 y
check_exact CONFIG_PACKAGE_trusted-firmware-a-s5p6818 y

# Cold product builds must use OpenWrt's own toolchain and no ccache.
if grep -Fqx 'CONFIG_EXTERNAL_TOOLCHAIN=y' "$config"; then
	echo 'FAIL: external toolchain is enabled' >&2
	fail=1
fi
if grep -Fqx 'CONFIG_CCACHE=y' "$config"; then
	echo 'FAIL: ccache is enabled' >&2
	fail=1
fi
if ! grep -Fqx 'CONFIG_CCACHE_DIR=""' "$config"; then
	echo 'FAIL: CONFIG_CCACHE_DIR is not empty' >&2
	fail=1
fi

if grep -Eq '^CONFIG_(DEVEL|SRC_TREE_OVERRIDE)=y$' "$config"; then
	echo 'NOTICE: development/source-tree override is enabled; this is not a release-closed configuration' >&2
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo 'x6818 config checks passed (development/source override status is informational)'
