# SPDX-License-Identifier: GPL-2.0-only
# Development-only source exports until immutable release downloads exist.
# Check on every configure, including an already prepared .source_dir tree.
define Build/NexellCheckSource
	@test -n "$(USE_SOURCE_DIR)" || { echo "$(PKG_NAME): explicit local source is required; release source gate is closed" >&2; exit 1; }
	@test -d "$(USE_SOURCE_DIR)" || { echo "$(PKG_NAME): local source directory is missing" >&2; exit 1; }
	@test "$(USE_SOURCE_DIR)" -ef "$(PKG_BUILD_DIR)" || { echo "$(PKG_NAME): prepared source differs from requested export; use a fresh package build directory" >&2; exit 1; }
endef

Hooks/Configure/Pre += Build/NexellCheckSource
