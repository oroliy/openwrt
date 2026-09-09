#!/bin/sh
# Verify the x6818 feed lock without fetching, checking out, or deleting.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TOPDIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CONFIG=$TOPDIR/configs/x6818.feeds.conf

[ -r "$CONFIG" ] || {
	echo "missing feed lock: $CONFIG" >&2
	exit 1
}

EFFECTIVE_CONFIG=${X6818_EFFECTIVE_FEEDS_CONF:-$TOPDIR/feeds.conf}
[ -r "$EFFECTIVE_CONFIG" ] || {
	echo "missing effective feeds.conf (or X6818_EFFECTIVE_FEEDS_CONF): $EFFECTIVE_CONFIG" >&2
	exit 1
}
cmp -s "$CONFIG" "$EFFECTIVE_CONFIG" || {
	echo "effective feeds.conf differs from x6818 lock" >&2
	exit 1
}

extra_source=$(awk '$1 ~ /^src-/ && $1 != "src-git-full" { print $1; bad = 1 } END { if (bad) exit 0; exit 1 }' "$CONFIG" || true)
[ -z "$extra_source" ] || {
	echo "unsupported or floating feed source type: $extra_source" >&2
	exit 1
}

expected_feeds='packages luci routing telephony video'
line_count=$(awk '$1 == "src-git-full" { n++ } END { print n + 0 }' "$CONFIG")
[ "$line_count" -eq 5 ] || {
	echo "expected exactly five src-git-full entries, found $line_count" >&2
	exit 1
}

for feed in $expected_feeds; do
	entry=$(awk -v feed="$feed" \
		'$1 == "src-git-full" && $2 == feed { print $3; n++ } \
		END { if (n != 1) exit 1 }' "$CONFIG") || {
		echo "missing or duplicate locked entry: $feed" >&2
		exit 1
	}

	case "$entry" in
		*^*) : ;;
		*) echo "entry is not URL^SHA: $feed" >&2; exit 1 ;;
	esac
	url=${entry%%^*}
	sha=${entry##*^}
	case "$url" in
		https://*) : ;;
		*) echo "non-HTTPS feed URL: $feed" >&2; exit 1 ;;
	esac
	case "$sha" in
		????????????????????????????????????????) : ;;
		*) echo "feed revision is not a full 40-character SHA: $feed" >&2; exit 1 ;;
	esac
	case "$sha" in
		*[!0123456789abcdefABCDEF]*)
			echo "feed revision contains non-hex characters: $feed" >&2
			exit 1
		;;
	esac

	repo=$TOPDIR/feeds/$feed
	[ -d "$repo" ] || {
		echo "missing feed checkout: feeds/$feed" >&2
		exit 1
	}
	repo_real=$(CDPATH= cd -- "$repo" && pwd -P)
	git_root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || {
		echo "feed checkout is not an independent git repository: $feed" >&2
		exit 1
	}
	[ "$git_root" = "$repo_real" ] || {
		echo "feed checkout resolves to another git repository: $feed" >&2
		exit 1
	}

	actual=$(git -C "$repo" rev-parse --verify HEAD 2>/dev/null) || {
		echo "cannot read feed HEAD: $feed" >&2
		exit 1
	}
	[ "$actual" = "$sha" ] || {
		echo "feed HEAD mismatch: $feed expected $sha got $actual" >&2
		exit 1
	}

	status=$(git -C "$repo" status --porcelain)
	[ -z "$status" ] || {
		echo "dirty feed checkout: $feed" >&2
		exit 1
	}

	echo "OK $feed $actual clean"
done
