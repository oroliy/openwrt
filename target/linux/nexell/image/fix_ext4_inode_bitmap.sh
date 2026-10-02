#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Repair the known make_ext4fs inode-bitmap padding defect, then verify ext4.
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <e2fsck> <ext4-image> <source-date-epoch>" >&2
    exit 2
fi
FSCK="$1"
IMAGE="$2"
EPOCH="$3"
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

"$FSCK" -fn "$IMAGE"
