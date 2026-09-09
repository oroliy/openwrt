#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
platform="$root/base-files/lib/upgrade/platform.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
not_expect() { if "$@"; then fail "unexpected success: $*"; fi; }

# Source the production entry points without providing any block-device,
# partition, mount, or image helper.  A safe fail-closed implementation must
# reject before any of those interfaces are reached.
platform_calls=0
export_bootdevice() { platform_calls=$((platform_calls + 1)); return 0; }
export_partdevice() { platform_calls=$((platform_calls + 1)); return 0; }
get_partitions() { platform_calls=$((platform_calls + 1)); return 0; }
mount() { platform_calls=$((platform_calls + 1)); return 0; }
dd() { platform_calls=$((platform_calls + 1)); return 0; }

. "$platform"
printf image > "$tmp/image"
not_expect platform_check_image "$tmp/image"
not_expect platform_do_upgrade "$tmp/image"
not_expect platform_copy_config
[ "$platform_calls" -eq 0 ] || fail "unsupported sysupgrade touched a storage helper"
echo "ok: all sysupgrade/config entry points fail closed without storage access"

echo "upgrade tests: PASS"
