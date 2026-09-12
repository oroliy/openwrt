#!/usr/bin/env python3
"""Generate x6818 splash artwork in three formats.

- logo.bmp            : 24-bit BMP 1024x600 for U-Boot `bmp display`
                        (loaded from mmc 2:1 as logo.bmp)
- logo_data.inc       : raw BGR888 top-down bytes for U-Boot builtin_logo.c
- splash-x6818.raw    : X8R8G8B8 top-down (B,G,R,0xFF) for Linux /dev/fb0
                        (simplefb 1024x600x32, linelength 4096)
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 600

img = Image.new("RGB", (W, H))
px = img.load()
# vertical gradient: deep navy -> steel blue
for y in range(H):
    t = y / (H - 1)
    r = int(8 + 20 * t)
    g = int(24 + 52 * t)
    b = int(64 + 120 * t)
    for x in range(W):
        px[x, y] = (r, g, b)

d = ImageDraw.Draw(img)
# accent bars
d.rectangle([0, 0, W, 10], fill=(0, 200, 255))
d.rectangle([0, H - 10, W, H], fill=(0, 200, 255))
d.rectangle([40, 200, 56, 400], fill=(0, 200, 255))
d.rectangle([968, 200, 984, 400], fill=(0, 200, 255))

def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()

def center(y, text, fnt, fill):
    bb = d.textbbox((0, 0), text, font=fnt)
    d.text(((W - (bb[2] - bb[0])) / 2, y), text, font=fnt, fill=fill)

center(90, "Nexell S5P6818", font(72), (255, 255, 255))
center(190, "x6818  AArch64", font(56), (0, 220, 255))
center(300, "OpenWrt 25.12  -  Linux 6.12", font(36), (220, 235, 255))
center(370, "8x Cortex-A53  |  eMMC  |  GMAC  |  USB  |  WiFi/BT", font(28), (170, 200, 225))
center(450, "U-Boot 2026.07  +  TF-A PSCI", font(28), (170, 200, 225))
# status dots row
for i, (label, col) in enumerate([("PWR", (0, 255, 120)), ("CPU", (0, 255, 120)),
                                  ("NET", (0, 255, 120)), ("MMC", (255, 200, 0))]):
    x = 350 + i * 110
    d.ellipse([x, 500, x + 24, 524], fill=col)
    d.text((x + 32, 500), label, font=font(22), fill=(230, 240, 250))

img.save("/tmp/opencode/logo.bmp")

# BGR888 top-down bytes for logo_data.c
bgr = bytearray()
for y in range(H):
    for x in range(W):
        r, g, b = img.getpixel((x, y))
        bgr += bytes((b, g, r))
open("/tmp/opencode/logo_bgr888.bin", "wb").write(bgr)

# X8R8G8B8 top-down bytes (B,G,R,0xFF) for /dev/fb0
raw = bytearray()
for y in range(H):
    for x in range(W):
        r, g, b = img.getpixel((x, y))
        raw += bytes((b, g, r, 0xFF))
open("/tmp/opencode/splash-x6818.raw", "wb").write(raw)
print("bmp+bgr+raw done", len(bgr), len(raw))
