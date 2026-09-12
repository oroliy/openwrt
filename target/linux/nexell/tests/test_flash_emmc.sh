#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tool="$root/base-files/usr/sbin/x6818-flash-emmc"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
not_expect() { if "$@"; then fail "unexpected success: $*"; fi; }
sha() { sha256sum "$1" | awk '{ print $1 }'; }
size() { stat -c %s "$1"; }
run_tool() {
	image="$1"
	target="$2"
	expanded="$3"
	"$tool" "$image" "$target" "$(sha "$image")" "$(size "$expanded")" "$(sha "$expanded")"
}

[ -f "$tool" ] || fail "tool $tool missing"
[ -x "$tool" ] || fail "tool $tool not executable"

not_expect "$tool"
echo "ok: exact manifest arguments required"

not_expect "$tool" "$tmp/nonexistent.img" "$tmp/target" \
	"$(printf x | sha256sum | awk '{print $1}')" 1 \
	"$(printf x | sha256sum | awk '{print $1}')"
echo "ok: nonexistent image rejected"

touch "$tmp/zero.img" "$tmp/dummy_dev"
not_expect run_tool "$tmp/zero.img" "$tmp/dummy_dev" "$tmp/zero.img"
echo "ok: invalid MBR rejected"

python3 - "$tmp" <<'PY'
import pathlib, struct, sys
p = pathlib.Path(sys.argv[1])
no_nsih = bytearray(2048)
no_nsih[510:512] = b"\x55\xaa"
(p / "no_nsih.img").write_bytes(no_nsih)
sd = bytearray(no_nsih)
struct.pack_into("<I", sd, 1020, 0x4849534e)
sd[592] = 0
(p / "sd_channel0.img").write_bytes(sd)
emmc = bytearray(sd)
emmc[592] = 2
(p / "emmc_channel2.img").write_bytes(emmc)
PY

not_expect run_tool "$tmp/no_nsih.img" "$tmp/dummy_dev" "$tmp/no_nsih.img"
echo "ok: missing NSIH rejected"
not_expect run_tool "$tmp/sd_channel0.img" "$tmp/dummy_dev" "$tmp/sd_channel0.img"
echo "ok: channel 0 SD firmware rejected"

mock_proc="$tmp/proc"
fake_sys="$tmp/sys-class-block"
mkdir -p "$mock_proc" "$fake_sys"
echo "/dev/mmcblk1p2 / overlay rw 0 0" > "$mock_proc/mounts"

touch "$tmp/mounted_target_emmc"
real_mounted="$(readlink -f "$tmp/mounted_target_emmc")"
echo "${real_mounted}p1 /mnt/test ext4 rw 0 0" > "$mock_proc/mounted"
not_expect env X6818_PROC_MOUNTS="$mock_proc/mounted" \
	"$tool" "$tmp/emmc_channel2.img" "$tmp/mounted_target_emmc" \
	"$(sha "$tmp/emmc_channel2.img")" "$(size "$tmp/emmc_channel2.img")" \
	"$(sha "$tmp/emmc_channel2.img")"
[ ! -s "$tmp/mounted_target_emmc" ] || fail "mounted target was modified"
echo "ok: mounted target partition rejected"

touch "$tmp/sd_target"
mkdir -p "$fake_sys/sd_target/device"
echo SD > "$fake_sys/sd_target/device/type"
not_expect env X6818_SYS_CLASS_BLOCK="$fake_sys" \
	"$tool" "$tmp/emmc_channel2.img" "$tmp/sd_target" \
	"$(sha "$tmp/emmc_channel2.img")" "$(size "$tmp/emmc_channel2.img")" \
	"$(sha "$tmp/emmc_channel2.img")"
[ ! -s "$tmp/sd_target" ] || fail "SD-typed target was modified"
echo "ok: SD-typed target rejected"

touch "$tmp/partition_target"
mkdir -p "$fake_sys/partition_target"
touch "$fake_sys/partition_target/partition"
not_expect env X6818_SYS_CLASS_BLOCK="$fake_sys" \
	"$tool" "$tmp/emmc_channel2.img" "$tmp/partition_target" \
	"$(sha "$tmp/emmc_channel2.img")" "$(size "$tmp/emmc_channel2.img")" \
	"$(sha "$tmp/emmc_channel2.img")"
echo "ok: partition target rejected"

touch "$tmp/mmcblk0boot0"
not_expect run_tool "$tmp/emmc_channel2.img" "$tmp/mmcblk0boot0" "$tmp/emmc_channel2.img"
echo "ok: eMMC hardware boot-area target rejected"

touch "$tmp/small_emmc"
mkdir -p "$fake_sys/small_emmc/device"
echo MMC > "$fake_sys/small_emmc/device/type"
echo 1 > "$fake_sys/small_emmc/size"
not_expect env X6818_SYS_CLASS_BLOCK="$fake_sys" \
	"$tool" "$tmp/emmc_channel2.img" "$tmp/small_emmc" \
	"$(sha "$tmp/emmc_channel2.img")" "$(size "$tmp/emmc_channel2.img")" \
	"$(sha "$tmp/emmc_channel2.img")"
[ ! -s "$tmp/small_emmc" ] || fail "undersized target was modified"
echo "ok: undersized eMMC rejected"

mkdir -p "$tmp/fakebin"
cat > "$tmp/fakebin/dd" <<'EOF'
#!/bin/sh
out=
for arg in "$@"; do
	case "$arg" in of=*) out="${arg#of=}" ;; esac
done
/usr/bin/dd "$@"
rc=$?
if [ "$rc" -eq 0 ] && [ -n "${X6818_TEST_CORRUPT_TARGET:-}" ] && \
   [ "$out" = "$X6818_TEST_CORRUPT_TARGET" ]; then
	printf '\377' | /usr/bin/dd of="$out" bs=1 seek=1536 conv=notrunc status=none
fi
exit "$rc"
EOF
chmod +x "$tmp/fakebin/dd"
touch "$tmp/corrupt_target_emmc"
not_expect env PATH="$tmp/fakebin:$PATH" \
	X6818_TEST_CORRUPT_TARGET="$(readlink -f "$tmp/corrupt_target_emmc")" \
	"$tool" "$tmp/emmc_channel2.img" "$tmp/corrupt_target_emmc" \
	"$(sha "$tmp/emmc_channel2.img")" "$(size "$tmp/emmc_channel2.img")" \
	"$(sha "$tmp/emmc_channel2.img")"
echo "ok: payload corruption beyond headers rejected"

touch "$tmp/mock_target_emmc"
run_tool "$tmp/emmc_channel2.img" "$tmp/mock_target_emmc" "$tmp/emmc_channel2.img"
cmp "$tmp/emmc_channel2.img" "$tmp/mock_target_emmc" >/dev/null || fail "raw payload mismatch"
echo "ok: raw image passed full readback"

gzip -c "$tmp/emmc_channel2.img" > "$tmp/emmc_channel2.img.gz"
touch "$tmp/mock_target_emmc_gz"
run_tool "$tmp/emmc_channel2.img.gz" "$tmp/mock_target_emmc_gz" "$tmp/emmc_channel2.img"
cmp "$tmp/emmc_channel2.img" "$tmp/mock_target_emmc_gz" >/dev/null || fail "gzip payload mismatch"
echo "ok: gzip image passed full readback"

gzip_size="$(size "$tmp/emmc_channel2.img.gz")"
head -c "$((gzip_size - 4))" "$tmp/emmc_channel2.img.gz" > "$tmp/truncated.img.gz"
touch "$tmp/truncated_target_emmc"
not_expect run_tool "$tmp/truncated.img.gz" "$tmp/truncated_target_emmc" "$tmp/emmc_channel2.img"
[ ! -s "$tmp/truncated_target_emmc" ] || fail "truncated gzip modified target"
echo "ok: truncated gzip rejected before write"

# The writer dd can succeed after a short stream. The producer exit status
# must independently fail the operation.
mkdir -p "$tmp/fail-zcat-bin"
cat > "$tmp/fail-zcat-bin/zcat" <<EOF
#!/bin/sh
/usr/bin/head -c 1536 '$tmp/emmc_channel2.img'
exit 7
EOF
chmod +x "$tmp/fail-zcat-bin/zcat"
touch "$tmp/producer_failure_target"
not_expect env PATH="$tmp/fail-zcat-bin:$PATH" \
	"$tool" "$tmp/emmc_channel2.img.gz" "$tmp/producer_failure_target" \
	"$(sha "$tmp/emmc_channel2.img.gz")" "$(size "$tmp/emmc_channel2.img")" \
	"$(sha "$tmp/emmc_channel2.img")"
[ ! -s "$tmp/producer_failure_target" ] || fail "failed producer modified target"
echo "ok: decompressor producer failure rejected explicitly"

# ash defers traps while a foreground external command runs. Both FIFO ends
# must therefore be background jobs managed by the parent shell. Stop during
# the destructive write and prove that the script, producer, and writer exit.
mkdir -p "$tmp/signal-bin" "$tmp/signal-tmp"
cat > "$tmp/signal-bin/zcat" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$X6818_TEST_COUNT" ] || count="$(cat "$X6818_TEST_COUNT")"
count=$((count + 1))
echo "$count" > "$X6818_TEST_COUNT"
if [ "$count" -eq 3 ]; then
	head -c 1024 "$X6818_TEST_RAW"
	echo "$$" > "$X6818_TEST_CHILD_PID"
	: > "$X6818_TEST_MARKER"
	sleep 30
	dd if="$X6818_TEST_RAW" bs=1 skip=1024 2>/dev/null
else
	cat "$X6818_TEST_RAW"
fi
EOF
chmod +x "$tmp/signal-bin/zcat"
touch "$tmp/signal_target"
env PATH="$tmp/signal-bin:$PATH" TMPDIR="$tmp/signal-tmp" \
	X6818_TEST_COUNT="$tmp/signal-count" \
	X6818_TEST_RAW="$tmp/emmc_channel2.img" \
	X6818_TEST_CHILD_PID="$tmp/signal-child-pid" \
	X6818_TEST_MARKER="$tmp/signal-marker" \
	"$tool" "$tmp/emmc_channel2.img.gz" "$tmp/signal_target" \
	"$(sha "$tmp/emmc_channel2.img.gz")" "$(size "$tmp/emmc_channel2.img")" \
	"$(sha "$tmp/emmc_channel2.img")" > "$tmp/signal.log" 2>&1 &
script_pid="$!"
i=0
while [ ! -f "$tmp/signal-marker" ] && [ "$i" -lt 50 ]; do
	sleep 0.1
	i=$((i + 1))
done
[ -f "$tmp/signal-marker" ] || {
	kill "$script_pid" 2>/dev/null || true
	fail "write-stage signal fixture did not start"
}
child_pid="$(cat "$tmp/signal-child-pid")"
kill -TERM "$script_pid"
i=0
while kill -0 "$script_pid" 2>/dev/null && [ "$i" -lt 50 ]; do
	sleep 0.1
	i=$((i + 1))
done
if kill -0 "$script_pid" 2>/dev/null; then
	kill -KILL "$script_pid" "$child_pid" 2>/dev/null || true
	fail "installer did not exit promptly after TERM"
fi
wait "$script_pid" 2>/dev/null || true
kill -0 "$child_pid" 2>/dev/null && fail "decompressor survived installer TERM"
before="$(size "$tmp/signal_target")"
sleep 0.2
after="$(size "$tmp/signal_target")"
[ "$before" = "$after" ] || fail "target kept growing after installer TERM"
if find "$tmp/signal-tmp" -mindepth 1 -print -quit | grep -q .; then
	fail "installer left FIFO or temporary files after TERM"
fi
echo "ok: TERM stops write producer and consumer and removes temporary files"

echo "flash emmc recovery tests: PASS"
