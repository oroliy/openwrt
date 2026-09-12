# SPDX-License-Identifier: GPL-2.0-only
# Validate an explicitly requested development source export on every
# configure, including an already prepared .source_dir tree.  With no
# USE_SOURCE_DIR, the package uses its pinned remote source normally.
define Build/NexellCheckSource
	@test -z "$(USE_SOURCE_DIR)" || test -d "$(USE_SOURCE_DIR)" || { echo "$(PKG_NAME): local source directory is missing" >&2; exit 1; }
	@test -z "$(USE_SOURCE_DIR)" || test "$(USE_SOURCE_DIR)" -ef "$(PKG_BUILD_DIR)" || { echo "$(PKG_NAME): prepared source differs from requested export; use a fresh package build directory" >&2; exit 1; }
endef

Hooks/Configure/Pre += Build/NexellCheckSource
