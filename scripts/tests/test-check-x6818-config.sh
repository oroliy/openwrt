#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
checker=$root/scripts/check-x6818-config.sh
tmp=$(mktemp -d "${TMPDIR:-/tmp}/x6818-config-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cat >"$tmp/seed" <<'EOF'
CONFIG_TARGET_nexell_s5p6818_arm64=y
CONFIG_PACKAGE_luci=y
EOF
cat >"$tmp/good" <<'EOF'
CONFIG_TARGET_nexell_s5p6818_arm64=y
CONFIG_PACKAGE_luci=y
CONFIG_ARCH="aarch64"
CONFIG_ARCH_64BIT=y
CONFIG_TARGET_ARCH_PACKAGES="aarch64_cortex-a53"
CONFIG_PACKAGE_nexell-firmware=y
CONFIG_PACKAGE_u-boot-x6818_arm64=y
CONFIG_PACKAGE_trusted-firmware-a-s5p6818=y
# CONFIG_EXTERNAL_TOOLCHAIN is not set
# CONFIG_CCACHE is not set
CONFIG_CCACHE_DIR=""
CONFIG_DEVEL=y
CONFIG_SRC_TREE_OVERRIDE=y
EOF

"$checker" "$tmp/seed" "$tmp/good" >"$tmp/out"
grep -Fq 'passed' "$tmp/out"

cp "$tmp/good" "$tmp/changed"
sed -i 's/CONFIG_PACKAGE_luci=y/CONFIG_PACKAGE_luci=n/' "$tmp/changed"
if "$checker" "$tmp/seed" "$tmp/changed" >"$tmp/changed.out" 2>&1; then
	echo 'negative changed-value fixture unexpectedly passed' >&2
	exit 1
fi
grep -Fq 'CONFIG_PACKAGE_luci=y' "$tmp/changed.out"

cp "$tmp/good" "$tmp/missing"
sed -i '/CONFIG_PACKAGE_u-boot-x6818_arm64=y/d' "$tmp/missing"
if "$checker" "$tmp/seed" "$tmp/missing" >"$tmp/missing.out" 2>&1; then
	echo 'negative missing-runtime-package fixture unexpectedly passed' >&2
	exit 1
fi
grep -Fq 'CONFIG_PACKAGE_u-boot-x6818_arm64=y' "$tmp/missing.out"

cp "$tmp/good" "$tmp/external"
sed -i 's/# CONFIG_EXTERNAL_TOOLCHAIN is not set/CONFIG_EXTERNAL_TOOLCHAIN=y/' "$tmp/external"
if "$checker" "$tmp/seed" "$tmp/external" >"$tmp/external.out" 2>&1; then
	echo 'negative external-toolchain fixture unexpectedly passed' >&2
	exit 1
fi
grep -Fq 'external toolchain is enabled' "$tmp/external.out"

cp "$tmp/good" "$tmp/ccache"
sed -i 's/# CONFIG_CCACHE is not set/CONFIG_CCACHE=y/' "$tmp/ccache"
if "$checker" "$tmp/seed" "$tmp/ccache" >"$tmp/ccache.out" 2>&1; then
	echo 'negative ccache fixture unexpectedly passed' >&2
	exit 1
fi
grep -Fq 'ccache is enabled' "$tmp/ccache.out"

cp "$tmp/good" "$tmp/wrongarch"
sed -i 's/CONFIG_ARCH="aarch64"/CONFIG_ARCH="arm"/' "$tmp/wrongarch"
if "$checker" "$tmp/seed" "$tmp/wrongarch" >"$tmp/wrongarch.out" 2>&1; then
	echo 'negative wrong-architecture fixture unexpectedly passed' >&2
	exit 1
fi
grep -Fq 'CONFIG_ARCH="aarch64"' "$tmp/wrongarch.out"

echo 'check-x6818-config fixtures: PASS'
