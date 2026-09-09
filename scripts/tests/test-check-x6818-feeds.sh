#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/x6818-feed-check.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail()
{
	echo "FAIL: $*" >&2
	exit 1
}

make_fixture()
{
	case_root=$TMP_ROOT/$1
	mkdir -p "$case_root/feeds" "$case_root/configs" "$case_root/scripts"
	cp "$ROOT/scripts/check-x6818-feeds.sh" "$case_root/scripts/check-x6818-feeds.sh"
	chmod +x "$case_root/scripts/check-x6818-feeds.sh"

	for feed in packages luci routing telephony video; do
		repo=$case_root/feeds/$feed
		mkdir -p "$repo"
		git -C "$repo" init -q
		git -C "$repo" config user.email test@example.invalid
		git -C "$repo" config user.name fixture
		printf '%s\n' "$feed fixture" > "$repo/README"
		git -C "$repo" add README
		git -C "$repo" commit -q -m initial
		sha=$(git -C "$repo" rev-parse HEAD)
		printf '%s %s\n' "$feed" "$sha" >> "$case_root/sha"
	done

	{
		while read -r feed sha; do
			printf 'src-git-full %s https://example.invalid/%s.git^%s\n' "$feed" "$feed" "$sha"
		done < "$case_root/sha"
	} > "$case_root/configs/x6818.feeds.conf"
	cp "$case_root/configs/x6818.feeds.conf" "$case_root/feeds.conf"
}

expect_ok()
{
	case_root=$1
	output=$($case_root/scripts/check-x6818-feeds.sh 2>&1) || {
		echo "$output" >&2
		fail "expected success: $case_root"
	}
	printf '%s\n' "$output" | grep -q '^OK packages ' || fail "missing success evidence"
}

expect_fail()
{
	case_root=$1
	pattern=$2
	if output=$($case_root/scripts/check-x6818-feeds.sh 2>&1); then
		echo "$output" >&2
		fail "expected failure: $case_root"
	fi
	printf '%s\n' "$output" | grep -q "$pattern" || {
		echo "$output" >&2
		fail "failure did not mention $pattern"
	}
}

case_root=$TMP_ROOT/pass
make_fixture pass
expect_ok "$case_root"

case_root=$TMP_ROOT/missing
make_fixture missing
rm -rf "$case_root/feeds/video"
expect_fail "$case_root" 'missing feed checkout: feeds/video'

case_root=$TMP_ROOT/wrong-head
make_fixture wrong-head
printf 'new commit\n' >> "$case_root/feeds/packages/README"
git -C "$case_root/feeds/packages" add README
git -C "$case_root/feeds/packages" commit -q -m changed
expect_fail "$case_root" 'feed HEAD mismatch: packages'

case_root=$TMP_ROOT/tracked-dirty
make_fixture tracked-dirty
printf 'dirty\n' >> "$case_root/feeds/luci/README"
expect_fail "$case_root" 'dirty feed checkout: luci'

case_root=$TMP_ROOT/untracked
make_fixture untracked
printf 'untracked\n' > "$case_root/feeds/routing/untracked"
expect_fail "$case_root" 'dirty feed checkout: routing'

case_root=$TMP_ROOT/duplicate
make_fixture duplicate
sed -n '1p' "$case_root/configs/x6818.feeds.conf" >> "$case_root/configs/x6818.feeds.conf"
cp "$case_root/configs/x6818.feeds.conf" "$case_root/feeds.conf"
expect_fail "$case_root" 'expected exactly five src-git-full entries'

case_root=$TMP_ROOT/invalid-sha
make_fixture invalid-sha
sed -i '1s/\^.*$/^not-a-full-sha/' "$case_root/configs/x6818.feeds.conf"
cp "$case_root/configs/x6818.feeds.conf" "$case_root/feeds.conf"
expect_fail "$case_root" 'feed revision is not a full 40-character SHA: packages'

case_root=$TMP_ROOT/extra-source
make_fixture extra-source
printf '%s\n' 'src-git floating https://example.invalid/floating.git;openwrt-25.12' >> "$case_root/configs/x6818.feeds.conf"
cp "$case_root/configs/x6818.feeds.conf" "$case_root/feeds.conf"
expect_fail "$case_root" 'unsupported or floating feed source type: src-git'

case_root=$TMP_ROOT/effective-mismatch
make_fixture effective-mismatch
printf '%s\n' '# mismatch' >> "$case_root/feeds.conf"
expect_fail "$case_root" 'effective feeds.conf differs from x6818 lock'

case_root=$TMP_ROOT/parent-repository
make_fixture parent-repository
git -C "$case_root" init -q
git -C "$case_root" config user.email test@example.invalid
git -C "$case_root" config user.name fixture
printf '%s\n' parent > "$case_root/parent-file"
git -C "$case_root" add parent-file
git -C "$case_root" commit -q -m parent
rm -rf "$case_root/feeds/video/.git"
expect_fail "$case_root" 'feed checkout resolves to another git repository: video'

echo 'PASS: x6818 feed validator positive and negative fixtures'
