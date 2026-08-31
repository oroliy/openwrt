# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 x6818 port
#

ARCH:=aarch64
SUBTARGET:=s5p6818_arm64
BOARDNAME:=Nexell S5P6818 x6818 (AArch64)
CPU_TYPE:=cortex-a53
KERNELNAME:=Image dtbs

define Target/Description
	Build AArch64 images for the Nexell S5P6818 x6818 board using TF-A,
	PSCI, and the Linux arm64 Image boot protocol.
endef
