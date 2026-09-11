# SPDX-License-Identifier: GPL-2.0-only

# AArch64 uses booti with an uncompressed Image. The addresses keep
# the kernel clear of U-Boot at 0x43c00000, the framebuffer reservation at
# 0x46000000, and the secure-firmware reservation above 0x7e000000.

define Device/Default
  PROFILES := Default
  DEVICE_DTS_DIR := $(DTS_DIR)/nexell
  KERNEL_NAME := Image
  KERNEL_LOADADDR := 0x48000000
  KERNEL_ENTRY := 0x48000000
  KERNEL := kernel-bin
  KERNEL_INITRAMFS := kernel-bin
  IMAGES := sdcard.img.gz emmc.img.gz
  IMAGE/sdcard.img.gz := boot-common | nexell-sdcard | append-metadata | gzip
  IMAGE/emmc.img.gz := boot-common | nexell-emmc | append-metadata | gzip
endef

define Device/nexell_x6818_arm64
  DEVICE_VENDOR := Nexell
  DEVICE_MODEL := x6818 (AArch64)
  DEVICE_DTS := s5p6818-x6818-nexell-timer
  SUPPORTED_DEVICES := nexell,x6818
  DEVICE_PACKAGES := nexell-firmware kmod-rtl8xxxu rtl8723bu-firmware kmod-btusb bluez-daemon bluez-utils bluez-utils-extra bluez-libs kmod-input-evdev evtest iw kmod-input-gpio-keys-polled kmod-leds-gpio
  ARTIFACTS := Image Image-initramfs fit-initramfs dtb
  ARTIFACT/Image := copy-file $(KDIR)/Image
  ARTIFACT/Image-initramfs := copy-file $(KDIR)/Image-initramfs
  ARTIFACT/fit-initramfs := copy-file $(KDIR)/Image-initramfs | fit none $(KDIR)/image-s5p6818-x6818-nexell-timer.dtb | pad-to 512
  ARTIFACT/dtb := copy-file $(KDIR)/image-s5p6818-x6818-nexell-timer.dtb
endef
TARGET_DEVICES += nexell_x6818_arm64
