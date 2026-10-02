#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Repair the known make_ext4fs inode-bitmap padding defect, then verify ext4.
set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <e2fsck> <debugfs> <ext4-image> <source-date-epoch>" >&2
    exit 2
fi
FSCK="$1"
DEBUGFS="$2"
IMAGE="$3"
EPOCH="$4"
case "$EPOCH" in
    ''|*[!0-9]*) echo "invalid source date epoch" >&2; exit 2 ;;
esac

check_log="$(mktemp)"
trap 'rm -f "$check_log"' EXIT
status=0
"$FSCK" -fn "$IMAGE" >"$check_log" 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    exit 0
fi
if [ "$status" -ne 4 ] ||
   [ "$(grep -c 'Fix? no' "$check_log" || :)" -ne 1 ] ||
   ! grep -Fq 'Padding at end of inode bitmap is not set. Fix? no' "$check_log"; then
    cat "$check_log" >&2
    echo "unexpected ext4 filesystem error; refusing automatic repair" >&2
    exit 1
fi

status=0
E2FSPROGS_FAKE_TIME="$EPOCH" "$FSCK" -fy "$IMAGE" >"$check_log" 2>&1 || status=$?
if [ "$status" -ne 1 ] ||
   [ "$(grep -c 'Fix? yes' "$check_log" || :)" -ne 1 ] ||
   ! grep -Fq 'Padding at end of inode bitmap is not set. Fix? yes' "$check_log"; then
    cat "$check_log" >&2
    echo "ext4 bitmap repair did not match the known defect" >&2
    exit 1
fi

# Staged e2fsck records its wall-clock check/write time even with the fake
# clock set.  debugfs honors that clock and updates both superblock fields.
E2FSPROGS_FAKE_TIME="$EPOCH" "$DEBUGFS" -w \
    -R "set_super_value lastcheck @$EPOCH" "$IMAGE"
python3 - "$IMAGE" "$EPOCH" <<'PY'
import struct
import sys

with open(sys.argv[1], "rb") as image:
    image.seek(1024)
    superblock = image.read(128)
expected = int(sys.argv[2])
write_time = struct.unpack_from("<I", superblock, 48)[0]
check_time = struct.unpack_from("<I", superblock, 64)[0]
if (write_time, check_time) != (expected, expected):
    raise SystemExit("ext4 superblock time does not match source date epoch")
PY

"$FSCK" -fn "$IMAGE"
