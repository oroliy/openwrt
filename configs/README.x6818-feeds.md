# x6818 fixed feeds

`x6818.feeds.conf` pins every feed from the original `feeds.conf.default` to
the complete local repository revision observed on 2026-09-08.  The local
repositories were clean and on the `openwrt-25.12` branch:

| feed | URL | exact HEAD | local status |
| --- | --- | --- | --- |
| packages | `https://git.openwrt.org/feed/packages.git` | `bc31bd613a8b67f97a4c4c3da688b4385452a31f` | clean |
| luci | `https://git.openwrt.org/project/luci.git` | `4fd72fddcaa8c113907992f6d66448aaf4ed4080` | clean |
| routing | `https://git.openwrt.org/feed/routing.git` | `e49d76035aafb85ddc993b59271d8c7ba56b5362` | clean |
| telephony | `https://git.openwrt.org/feed/telephony.git` | `2618106d5846a4a542fdf5809f0d3ed228ce439b` | clean |
| video | `https://github.com/openwrt/video.git` | `094bf58da6682f895255a35a84349a79dab4bf95` | clean |

The feed origins above are the configured formal remotes.  This review did
not fetch, contact, or otherwise validate remote reachability, and does not
claim that any remote still advertises these commits.  No dirty or unknown
feed was included; a future source checkout that is dirty, missing, or cannot
resolve one of these complete SHAs is a hard reproducibility gap.

## Why this syntax is fixed

The local `scripts/feeds` parser splits a feed source at `^` into
`base_commit` and `commit`.  For `src-git-full`, the pinned form invokes a
full clone followed by checkout of the exact commit.  A branch-only
`src-git ...;openwrt-25.12` line would remain floating and is intentionally
not used here.

## Offline and cold-build procedure

These steps are documentation only; this review did not run them, update
feeds, install feeds, or run OpenWrt make:

1. Copy this file to the integration tree as `feeds.conf` (do not edit the
   shared `feeds.conf.default`).
2. For an offline build, pre-stage `feeds/{packages,luci,routing,telephony,video}`
   from trusted archives or local mirrors, verify each exact SHA above, and
   keep each checkout clean.  Do not use a branch tip as a substitute.
3. Run `./scripts/feeds update -i` to create local indexes when using
   pre-staged offline checkouts (this does not fetch). Run
   `./scripts/check-x6818-feeds.sh` to verify the effective configuration,
   exact HEADs and clean states. Run `./scripts/feeds install -a` only after
   the five exact checkouts and their indexes are
   present.  For a genuinely cold network build, `./scripts/feeds update -a`
   with this pinned file uses the `src-git-full URL^SHA` form; verify the
   resulting HEADs and clean status before installation.

The integration-specific source overrides for the x6818 boot packages remain
separate from feed pinning and must be supplied independently.

The parent workspace's third-batch report records a subsequent successful
network fetch of all five pinned revisions into a new tree. This does not
close the separate BL2/TF-A/U-Boot source-publication gate.
