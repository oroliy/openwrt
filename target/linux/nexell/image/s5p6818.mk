# SPDX-License-Identifier: GPL-2.0-only

# Boot flow (uboot-lts): ext4load zImage + dtb, then
#   bootz ${loadaddr} - ${dtb_addr}
# or the raw-sector path: bootm <self-contained FIT @0x48000000>.
# RAM bring-up milestone: initramfs zImage + separate DTB + uImage artifacts.

define Device/Default
  PROFILES := Default
  DEVICE_DTS_DIR := $(DTS_DIR)/nexell
  KERNEL_NAME := zImage
  KERNEL_LOADADDR := 0x40008000
  KERNEL_ENTRY := 0x40008000
  KERNEL := kernel-bin
  KERNEL_INITRAMFS := kernel-bin
  IMAGES :=
endef

define Device/nexell_x6818
  DEVICE_VENDOR := Nexell
  DEVICE_MODEL := x6818
  DEVICE_DTS := s5p6818-x6818
  SUPPORTED_DEVICES := nexell,x6818
  ARTIFACTS := uImage uImage-initramfs emmc-initramfs dtb
  ARTIFACT/uImage := copy-file $(KDIR)/zImage | uImage none
  ARTIFACT/uImage-initramfs := copy-file $(KDIR)/zImage-initramfs | uImage none
  ARTIFACT/emmc-initramfs := copy-file $(KDIR)/zImage-initramfs | fit none $(KDIR)/image-s5p6818-x6818.dtb | pad-to 512
  ARTIFACT/dtb := copy-file $(KDIR)/image-s5p6818-x6818.dtb
endef
TARGET_DEVICES += nexell_x6818

# v1 milestone is RAM initramfs boot: this device ships no combined
# rootfs images yet, so provide the empty images stamp the artifact
# rules depend on (normally created per IMAGE/ entry).
nexell_x6818-images:
