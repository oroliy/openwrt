#!/bin/sh
set -eu

script=$(CDPATH= cd -- "$(dirname "$0")/../base-files/etc/uci-defaults" && pwd)/99-resize-overlay
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"; mkdir -p "$bin"
logger_bin="$tmp/logger-bin"; mkdir -p "$logger_bin"
printf '#!/bin/sh\nexit 0\n' > "$bin/logger"
cp "$bin/logger" "$logger_bin/logger"
ln -s "$(command -v awk)" "$logger_bin/awk"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$1" >> "$RESIZE_LOG"' 'exit "${RESIZE_RC:-0}"' > "$bin/resize2fs"
chmod +x "$bin/logger" "$bin/resize2fs"
chmod +x "$logger_bin/logger"
backing="$tmp/overlay.img"; touch "$backing"; mounts="$tmp/mounts"
printf '%s /overlay ext4 rw 0 0\n' "$backing" > "$mounts"

# Source the hook in this shell so the test can mock only the block-device
# predicate. The production hook still uses the real `test -b` builtin.
test_backing=$backing
test() {
	if command [ "$1" = -b ] && command [ "$2" = "$test_backing" ]; then
		return 0
	fi
	command test "$@"
}
run_hook() {
	log=$1
	mounts_file=${2:-$mounts}
	( export RESIZE_LOG=$log PATH="${3:-$bin:$PATH}" OVERLAY_MOUNTS_FILE="$mounts_file"; . "$script" )
}

run_hook "$tmp/log"
[ "$(sed -n '1p' "$tmp/log")" = "$backing" ] || { echo "FAIL: mounted ext4 backing path was not passed to resize2fs" >&2; exit 1; }
echo "ok: actual mounted ext4 backing is selected"
run_hook "$tmp/log.idempotent"
[ "$(sed -n '1p' "$tmp/log.idempotent")" = "$backing" ] || { echo "FAIL: repeated resize did not remain idempotent" >&2; exit 1; }
echo "ok: repeated successful resize remains idempotent"
if RESIZE_RC=1 run_hook "$tmp/log.fail"; then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] || { echo "FAIL: resize failure was swallowed" >&2; exit 1; }
echo "ok: resize failure propagates"

for fs in squashfs tmpfs f2fs; do
	printf '%s /overlay %s rw 0 0\n' "$backing" "$fs" > "$mounts"
	if run_hook "$tmp/log.$fs"; then rc=0; else rc=$?; fi
	[ "$rc" -ne 0 ] || { echo "FAIL: unsupported filesystem was reported complete" >&2; exit 1; }
	[ ! -s "$tmp/log.$fs" ] || { echo "FAIL: non-ext4 filesystem was resized" >&2; exit 1; }
done
echo "ok: non-ext4 overlays remain pending"

printf '%s /overlay ext4 ro 0 0\n' "$backing" > "$mounts"
if RESIZE_LOG="$tmp/log.ro" run_hook "$tmp/log.ro"; then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] || { echo "FAIL: read-only ext4 overlay was reported complete" >&2; exit 1; }
echo "ok: read-only ext4 overlay is deferred"

printf '%s /overlay ext4 rw 0 0\n' "$tmp/missing.img" > "$mounts"
if RESIZE_LOG="$tmp/log.missing" run_hook "$tmp/log.missing"; then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] || { echo "FAIL: missing backing was reported complete" >&2; exit 1; }
echo "ok: missing backing fails closed"

if run_hook "$tmp/log.proc" "$tmp/missing-mounts"; then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] || { echo "FAIL: mounts read failure was reported complete" >&2; exit 1; }
echo "ok: mounts read failure remains retryable"
printf '%s /overlay ext4 rw 0 0\n' "$backing" > "$mounts"
# All earlier gates pass. Only the isolated PATH lacks resize2fs.
if run_hook "$tmp/log.no-resize" "$mounts" "$logger_bin"; then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] || { echo "FAIL: missing resize2fs was reported complete" >&2; exit 1; }
[ ! -s "$tmp/log.no-resize" ] || { echo "FAIL: resize2fs unexpectedly ran" >&2; exit 1; }
echo "ok: missing resize2fs remains retryable"
printf '%s /not-overlay ext4 rw 0 0\n' "$backing" > "$mounts"
if run_hook "$tmp/log.no-mount"; then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] || { echo "FAIL: missing overlay mount was reported complete" >&2; exit 1; }
echo "ok: missing overlay remains retryable"
echo "resize overlay tests: PASS"
