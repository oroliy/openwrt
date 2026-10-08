#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
not_expect() { if "$@"; then fail "unexpected success: $*"; fi; }

# Redirect only filesystem paths; invoke the production functions with real
# archive bytes and cp/mv/tar. No real device, mount, preinit or reboot runs.
sed -e 's@local mnt_dir="/tmp/sysupgrade_boot"@local mnt_dir="$case_dir/mount"@' \
 -e 's@\[ -f /lib/upgrade/common.sh \].*@: # fixture supplies dependencies@' \
 -e 's@" /$@" "$case_dir/root/"@' \
 -e 's@" /; then@" "$case_dir/root/"; then@' \
 -e 's@/tmp/.sysupgrade-restore-failed@$case_dir/root/tmp/.sysupgrade-restore-failed@g' \
 -e 's@/tmp/.sysupgrade-restore-complete@$case_dir/root/tmp/.sysupgrade-restore-complete@g' \
 "$root/target/linux/nexell/base-files/lib/preinit/79_move_config" > "$tmp/move.sh"
sed -e 's@^missing_lines()@real_missing_lines()@' \
 -e 's@/sysupgrade.tgz@$case_dir/root/sysupgrade.tgz@g' \
 -e 's@/tmp/sysupgrade.tar@$case_dir/root/tmp/sysupgrade.tar@g' \
 -e 's@/tmp/.sysupgrade-restore-failed@$case_dir/root/tmp/.sysupgrade-restore-failed@g' \
 -e 's@/tmp/.sysupgrade-restore-complete@$case_dir/root/tmp/.sysupgrade-restore-complete@g' \
 -e 's@/etc/passwd@$case_dir/root/etc/passwd@g' -e 's@/etc/group@$case_dir/root/etc/group@g' -e 's@/etc/shadow@$case_dir/root/etc/shadow@g' \
 -e 's@/tmp/passwd@$case_dir/root/tmp/passwd@g' -e 's@/tmp/group@$case_dir/root/tmp/group@g' -e 's@/tmp/shadow@$case_dir/root/tmp/shadow@g' \
 -e 's@/shadow /tmp@/shadow "$case_dir/root/tmp"@' -e 's@cd /@cd "$case_dir/root"@' \
 "$root/package/base-files/files/lib/preinit/80_mount_root" > "$tmp/restore.sh"
sed -e 's@/sysupgrade.tgz@$case_dir/root/sysupgrade.tgz@g' \
 -e 's@/tmp/sysupgrade.tar@$case_dir/root/tmp/sysupgrade.tar@g' \
 -e 's@/tmp/.sysupgrade-restore-failed@$case_dir/root/tmp/.sysupgrade-restore-failed@g' \
 -e 's@/tmp/.sysupgrade-restore-complete@$case_dir/root/tmp/.sysupgrade-restore-complete@g' \
 -e 's@/etc/rc.local@$case_dir/root/etc/rc.local@g' -e 's@\. /etc/diag.sh@: # fixture diag@' \
 "$root/package/base-files/files/etc/init.d/done" > "$tmp/done.sh"
INITRAMFS=0
boot_hook_add() { :; }
export_bootdevice() { return 0; }
export_partdevice() { eval "$1=\$case_dir/boot.img"; }
mkdir() { [ "$fail_mkdir" = 0 ] && command mkdir "$@"; }
mount() { [ "$fail_mount" = 0 ]; }
umount() { [ "$fail_umount" = 0 ]; }
mv() { [ "$fail_move" = 0 ] && command mv "$@"; }
tar() {
 case "$1" in x*) [ "$fail_extract" = 0 ] || return 1 ;; esac
 command tar "$@"
}
sync() { :; }
mount_root() { [ "$1" != done ] || [ "$fail_finalize" = 0 ]; }
cd() { [ "$fail_cd" = 0 ] && command cd "$@"; }
missing_lines() { [ "$fail_merge" = 0 ] && real_missing_lines "$@"; }
boot_run_hook() {
 [ "$run_move_hook" = 0 ] || move_config || true
 # Match preinit's dispatcher, which does not propagate callback failures.
 return 0
}
set_state() { :; }
. "$tmp/move.sh"
. "$tmp/restore.sh"
. "$tmp/done.sh"
compose_rootfs_mount_options() { :; }
new_case() {
 case_dir="$tmp/$1"
 command mkdir -p "$case_dir/mount" "$case_dir/root/etc/config" "$case_dir/root/tmp" "$case_dir/input/etc/config"
 printf 'root:x:0:0:root:/root:/bin/ash\n' > "$case_dir/root/etc/passwd"
 printf 'root:x:0:\n' > "$case_dir/root/etc/group"
 printf 'root:!:0:0:99999:7:::\n' > "$case_dir/root/etc/shadow"
 printf 'X6818_RESTORE_TOKEN\n' > "$case_dir/input/etc/config/token"
 chmod 640 "$case_dir/input/etc/config/token"
 ln -s token "$case_dir/input/etc/config/token-link"
 command tar czf "$case_dir/mount/sysupgrade.tgz" -C "$case_dir/input" etc
 fail_move=0; fail_umount=0; fail_extract=0; run_move_hook=0
 fail_mkdir=0; fail_mount=0; fail_cd=0; fail_merge=0; fail_finalize=0
}
preserved_failure() {
 [ -f "$case_dir/root/tmp/.sysupgrade-restore-failed" ] || fail "restore failure marker absent"
 not_expect boot
 [ -f "$case_dir/root/sysupgrade.tgz" ] || fail "failed restore archive was deleted by done"
}
new_case positive
move_config || fail 'move failed'
[ ! -e "$case_dir/mount/sysupgrade.tgz" ] || fail 'boot archive not moved'
do_mount_root || fail 'restore failed'
cmp "$case_dir/input/etc/config/token" "$case_dir/root/etc/config/token" || fail 'token bytes changed'
[ "$(LC_ALL=C ls -ld "$case_dir/root/etc/config/token" | cut -c 1-10)" = -rw-r----- ] || fail 'mode changed'
[ "$(readlink "$case_dir/root/etc/config/token-link")" = token ] || fail 'symlink changed'
boot || fail 'done failed after successful restore'
[ ! -e "$case_dir/root/sysupgrade.tgz" ] || fail 'successful archive not cleaned up'
echo 'ok: configuration archive round trip preserves bytes, mode and symlink'

for failure in mkdir mount; do
 new_case "$failure-failed"
 eval "fail_$failure=1"
 not_expect move_config
 [ -f "$case_dir/mount/sysupgrade.tgz" ] || fail "$failure failure lost boot backup"
 [ -f "$case_dir/root/tmp/.sysupgrade-restore-failed" ] || fail "$failure failure marker absent"
 not_expect do_mount_root
 not_expect boot
 echo "ok: failed $failure propagates and preserves boot backup"
done

new_case move-failed; fail_move=1
not_expect move_config
[ -f "$case_dir/mount/sysupgrade.tgz" ] || fail 'failed move lost boot backup'
[ -f "$case_dir/root/tmp/.sysupgrade-restore-failed" ] || fail 'failed move marker absent'
not_expect do_mount_root
not_expect boot
echo 'ok: failed move is propagated and retains the boot backup'

new_case hook-failed; fail_move=1; run_move_hook=1
not_expect do_mount_root
[ -f "$case_dir/root/tmp/.sysupgrade-restore-failed" ] || fail 'dispatcher hid restore failure'
echo 'ok: failed restore hook remains visible through the preinit dispatcher'

new_case umount-failed; fail_umount=1
not_expect move_config
preserved_failure
echo 'ok: failed restore unmount is propagated and preserves archive'

new_case corrupt-boot
printf 'invalid gzip\n' > "$case_dir/mount/sysupgrade.tgz"
not_expect move_config
[ -f "$case_dir/mount/sysupgrade.tgz" ] || fail 'corrupt boot archive consumed'
[ ! -e "$case_dir/root/sysupgrade.tgz" ] || fail 'corrupt archive moved into root'
echo 'ok: corrupt boot archive is rejected before consuming it'

new_case corrupt-root
printf 'invalid gzip\n' > "$case_dir/root/sysupgrade.tgz"
not_expect do_mount_root
preserved_failure
[ ! -e "$case_dir/root/etc/config/token" ] || fail 'corrupt archive altered config'
echo 'ok: corrupt archive stops restoration and survives done'

new_case extract-failed
command mv "$case_dir/mount/sysupgrade.tgz" "$case_dir/root/sysupgrade.tgz"
fail_extract=1
not_expect do_mount_root
preserved_failure
[ ! -e "$case_dir/root/etc/config/token" ] || fail 'injected extraction failure altered config'
echo 'ok: extraction I/O failure stops restoration and preserves archive'

for failure in cd merge; do
 new_case "$failure-failed"
 command mv "$case_dir/mount/sysupgrade.tgz" "$case_dir/root/sysupgrade.tgz"
 eval "fail_$failure=1"
 not_expect do_mount_root
 preserved_failure
 echo "ok: failed $failure preserves restoration evidence"
done

new_case marker-unwritable
command mv "$case_dir/mount/sysupgrade.tgz" "$case_dir/root/sysupgrade.tgz"
command mkdir "$case_dir/root/tmp/.sysupgrade-restore-complete"
command mkdir "$case_dir/root/tmp/.sysupgrade-restore-failed"
not_expect do_mount_root
not_expect boot
[ -f "$case_dir/root/sysupgrade.tgz" ] || fail 'unwritable marker lost backup'
echo 'ok: unwritable failure/success markers cannot authorize backup removal'

new_case volumeless-finalize
move_config || fail 'move failed'
do_mount_root || fail 'restore failed'
fail_finalize=1
boot || fail 'volume-less root must allow normal done'
[ ! -e "$case_dir/root/sysupgrade.tgz" ] || fail 'valid backup not cleaned on volume-less root'
[ ! -e "$case_dir/root/tmp/.sysupgrade-restore-failed" ] || fail 'normal volume-less root marked failed'
echo 'ok: volume-less ext4/initramfs finalization keeps normal successful restore behavior'

new_case no-archive
rm "$case_dir/mount/sysupgrade.tgz"
do_mount_root || fail 'normal boot without backup failed'
boot || fail 'normal done without backup failed'
echo 'ok: ordinary boot without configuration archive is unchanged'
new_case raw-positive
command tar cf "$case_dir/root/tmp/sysupgrade.tar" -C "$case_dir/input" etc
do_mount_root || fail 'raw archive restore failed'
cmp "$case_dir/input/etc/config/token" "$case_dir/root/etc/config/token" || fail 'raw token bytes changed'
boot || fail 'done failed after raw archive restore'
[ ! -e "$case_dir/root/tmp/sysupgrade.tar" ] || fail 'raw archive not cleaned'
echo 'ok: uncompressed configuration archive restores and cleans up'

new_case raw-corrupt
printf 'invalid tar\n' > "$case_dir/root/tmp/sysupgrade.tar"
not_expect do_mount_root
not_expect boot
[ -f "$case_dir/root/tmp/.sysupgrade-restore-failed" ] || fail 'raw failure marker absent'
[ -f "$case_dir/root/tmp/sysupgrade.tar" ] || fail 'corrupt raw archive was deleted'
[ ! -e "$case_dir/root/etc/config/token" ] || fail 'corrupt raw archive altered config'
echo 'ok: corrupt uncompressed archive remains available for recovery'

new_case missing-account-input
not_expect real_missing_lines "$case_dir/root/tmp/missing-passwd" "$case_dir/root/etc/passwd"
echo 'ok: account input read failure is propagated'

new_case accounts
printf 'generated:x:123:123:current:/var:/bin/false\n' >> "$case_dir/root/etc/passwd"
printf 'root:x:0:0:restored:/root:/bin/ash\n' > "$case_dir/input/etc/passwd"
command tar czf "$case_dir/root/sysupgrade.tgz" -C "$case_dir/input" etc
do_mount_root || fail 'account restore failed'
grep -q '^root:x:0:0:restored:' "$case_dir/root/etc/passwd" || fail 'restored account was replaced'
[ "$(grep -c '^generated:' "$case_dir/root/etc/passwd")" = 1 ] || fail 'generated account was lost or duplicated'
boot || fail 'done failed after account merge'
echo 'ok: archive accounts win while generated accounts are retained once'
echo 'configuration restore tests: PASS'
