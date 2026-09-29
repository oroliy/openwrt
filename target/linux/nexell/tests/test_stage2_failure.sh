#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
stage2="$root/package/base-files/files/lib/upgrade/do_stage2"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sed 's@^\. /lib/functions.sh$@. "$X6818_TEST_FUNCTIONS"@' "$stage2" > "$tmp/do_stage2"
cat > "$tmp/functions.sh" <<'EOF'
include() { :; }
v() {
	printf '%s\n' "$*"
	case "$*" in
		*Rebooting*) exit 99 ;;
	esac
}
platform_do_upgrade() { [ "$X6818_TEST_FAIL" != upgrade ]; }
platform_copy_config() { [ "$X6818_TEST_FAIL" != backup ]; }
EOF

export X6818_TEST_FUNCTIONS="$tmp/functions.sh" IMAGE="$tmp/fixture.img"
expect_stop() {
	if sh "$tmp/do_stage2" > "$tmp/result" 2>&1; then
		echo "FAIL: stage2 reported success after $X6818_TEST_FAIL failed" >&2
		exit 1
	fi
	if grep -q 'Upgrade completed\|Rebooting system' "$tmp/result"; then
		echo "FAIL: stage2 continued after $X6818_TEST_FAIL failed" >&2
		cat "$tmp/result" >&2
		exit 1
	fi
}

export X6818_TEST_FAIL=upgrade UPGRADE_BACKUP=
expect_stop
echo "ok: stage2 stops when platform_do_upgrade fails"

export X6818_TEST_FAIL=backup UPGRADE_BACKUP="$tmp/backup.tgz"
expect_stop
echo "ok: stage2 stops when platform_copy_config fails"

sed '/^platform_do_upgrade()/d' "$tmp/functions.sh" > "$tmp/default-functions.sh"
printf '%s\n' 'default_do_upgrade() { return 1; }' >> "$tmp/default-functions.sh"
export X6818_TEST_FUNCTIONS="$tmp/default-functions.sh" X6818_TEST_FAIL=default UPGRADE_BACKUP=
expect_stop
echo "ok: stage2 stops when default_do_upgrade fails"
