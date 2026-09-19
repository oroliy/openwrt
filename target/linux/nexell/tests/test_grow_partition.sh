#!/bin/sh
set -eu

script=$(CDPATH= cd -- "$(dirname "$0")/../base-files/etc/uci-defaults" && pwd)/98-grow-partition
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin"
mkdir -p "$bin"
logger_bin="$tmp/logger-bin"
mkdir -p "$logger_bin"

printf '#!/bin/sh\nexit 0\n' > "$bin/logger"
cp "$bin/logger" "$logger_bin/logger"
ln -s "$(command -v awk)" "$logger_bin/awk"
ln -s "$(command -v sed)" "$logger_bin/sed"
ln -s "$(command -v cat)" "$logger_bin/cat"

printf '%s\n' '#!/bin/sh' 'printf "sfdisk %s\n" "$*" >> "$SFDISK_LOG"' 'cat > "$SFDISK_LOG.in"' 'exit "${SFDISK_RC:-0}"' > "$bin/sfdisk"
printf '%s\n' '#!/bin/sh' 'printf "partx %s\n" "$*" >> "$PARTX_LOG"' 'exit "${PARTX_RC:-0}"' > "$bin/partx"
printf '%s\n' '#!/bin/sh' 'printf "losetup %s\n" "$*" >> "$LOSETUP_LOG"' 'exit "${LOSETUP_RC:-0}"' > "$bin/losetup"
chmod +x "$bin/logger" "$logger_bin/logger" "$bin/sfdisk" "$bin/partx" "$bin/losetup"

mock_sys="$tmp/sys-class-block"
mkdir -p "$mock_sys/mmcblk0" "$mock_sys/mmcblk0p2"
echo 15269888 > "$mock_sys/mmcblk0/size"
echo 262144 > "$mock_sys/mmcblk0p2/start"
echo 1048576 > "$mock_sys/mmcblk0p2/size"

backing="/dev/mmcblk0p2"
mounts="$tmp/mounts"
printf '%s /overlay ext4 rw 0 0\n' "$backing" > "$mounts"

# Mock `test` builtin so test -b /dev/mmcblk0p2 succeeds
test() {
	if command [ "$1" = -b ] && command [ "$2" = "$backing" ]; then
		return 0
	fi
	command test "$@"
}

run_hook() {
	log=$1
	shift
	(
		export SFDISK_LOG="$log.sfdisk" PARTX_LOG="$log.partx" LOSETUP_LOG="$log.losetup" PATH="${1:-$bin:$PATH}"
		export OVERLAY_MOUNTS_FILE="$mounts" SYS_CLASS_BLOCK="$mock_sys" PROC_CMDLINE="${cmdline:-$tmp/cmdline}"
		. "$script"
	)
}

# 1. Normal run: unallocated space > 10MB, sfdisk + partx present
run_hook "$tmp/normal"
[ -f "$tmp/normal.sfdisk" ] || { echo "FAIL: sfdisk was not called" >&2; exit 1; }
grep -q "sfdisk -N 2 --no-reread /dev/mmcblk0" "$tmp/normal.sfdisk" || { echo "FAIL: unexpected sfdisk args" >&2; exit 1; }
grep -q ", +" "$tmp/normal.sfdisk.in" || { echo "FAIL: sfdisk did not receive resize script" >&2; exit 1; }
[ -f "$tmp/normal.partx" ] || { echo "FAIL: partx was not called" >&2; exit 1; }
echo "ok: unallocated space triggers sfdisk and partx resize"

# 2. /dev/root with cmdline PARTUUID resolution
printf 'root=PARTUUID=5452574f-02 console=ttySAC0\n' > "$tmp/cmdline"
printf 'PARTUUID=5452574f-02\n' > "$mock_sys/mmcblk0p2/uevent"
printf '/dev/root / ext4 rw 0 0\n' > "$mounts"
echo 1048576 > "$mock_sys/mmcblk0p2/size"
rm -f "$tmp/root-partuuid.sfdisk" "$tmp/root-partuuid.partx"
run_hook "$tmp/root-partuuid"
[ -f "$tmp/root-partuuid.sfdisk" ] || { echo "FAIL: /dev/root with PARTUUID did not trigger sfdisk" >&2; exit 1; }
grep -q "sfdisk -N 2 --no-reread /dev/mmcblk0" "$tmp/root-partuuid.sfdisk" || { echo "FAIL: unexpected sfdisk args for /dev/root" >&2; exit 1; }
echo "ok: /dev/root resolves via PARTUUID and triggers resize"

# 3. /dev/loop0 with backing_file resolution and loop capacity update
mkdir -p "$mock_sys/loop0/loop"
printf '/dev/mmcblk0p2\n' > "$mock_sys/loop0/loop/backing_file"
printf '/dev/loop0 /overlay ext4 rw 0 0\n' > "$mounts"
rm -f "$tmp/loop0.sfdisk" "$tmp/loop0.partx" "$tmp/loop0.losetup"
run_hook "$tmp/loop0"
[ -f "$tmp/loop0.sfdisk" ] || { echo "FAIL: /dev/loop0 did not trigger sfdisk" >&2; exit 1; }
grep -q "sfdisk -N 2 --no-reread /dev/mmcblk0" "$tmp/loop0.sfdisk" || { echo "FAIL: unexpected sfdisk args for /dev/loop0" >&2; exit 1; }
echo "ok: /dev/loop0 resolves backing_file and triggers resize"

# 4. Idempotent run: partition already spans the device
printf '%s /overlay ext4 rw 0 0\n' "$backing" > "$mounts"
echo 15007744 > "$mock_sys/mmcblk0p2/size"
rm -f "$tmp/idempotent.sfdisk" "$tmp/idempotent.partx"
run_hook "$tmp/idempotent"
[ ! -f "$tmp/idempotent.sfdisk" ] || { echo "FAIL: sfdisk called when partition already spans device" >&2; exit 1; }
echo "ok: already-expanded partition is skipped"

# 5. Missing sfdisk: exits cleanly without failure
echo 1048576 > "$mock_sys/mmcblk0p2/size"
run_hook "$tmp/no-sfdisk" "$logger_bin"
[ ! -f "$tmp/no-sfdisk.sfdisk" ] || { echo "FAIL: sfdisk ran when missing" >&2; exit 1; }
echo "ok: missing sfdisk fails open and does not crash"

# 6. Non-block backing: exits cleanly
test() { command test "$@"; }
run_hook "$tmp/non-block"
[ ! -f "$tmp/non-block.sfdisk" ] || { echo "FAIL: non-block backing triggered sfdisk" >&2; exit 1; }
echo "ok: non-block backing is skipped"

echo "grow partition tests: PASS"
