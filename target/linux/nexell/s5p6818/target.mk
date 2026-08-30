#
# Copyright (C) 2026 x6818 port
#

ARCH:=arm
SUBTARGET:=s5p6818
BOARDNAME:=Nexell S5P6818 x6818
CPU_TYPE:=cortex-a7
CPU_SUBTYPE:=neon-vfpv4
KERNELNAME:=zImage dtbs

define Target/Description
	Build images for the Nexell S5P6818 (8x Cortex-A53 AArch32) x6818 board.
endef
