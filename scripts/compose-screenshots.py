#!/usr/bin/env python3
"""Compose App Store screenshots from raw simulator captures.

Reads raws from claude-design/raw/ and writes 1290x2796 (IPHONE_67) PNGs to
claude-design/output/store/, ready for `fastlane deliver`.

The house style here is deliberately plain: a soft tinted canvas, a drawn
iPhone body with the real screen inside it, and one headline. The
app is for people looking after a parent, and a busy, over-designed store page
reads as a lifestyle product rather than the medication list they came for.

Copy rule (App Review 1.4.1, Medical category): nothing on these may claim to
treat, cure, diagnose or monitor anyone. Every caption below describes what the
app holds or shares, never a health outcome. No em dashes anywhere.

    ./scripts/compose-screenshots.py
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "claude-design", "raw")
OUT = os.path.join(ROOT, "claude-design", "output", "store")

# The 6.7" bucket. One set at this size covers the sizes ASC requires for
# submission; the 6.9" bucket accepts it too.
W, H = 1290, 2796

INK = (17, 24, 39)
BEZEL = (24, 25, 27)

# Tints, one per shot, all pulled around the app's own iOS blue so the set
# reads as one product rather than six unrelated cards.
TINTS = {
    "blue": ((219, 234, 254), (191, 219, 254)),
    "mint": ((209, 244, 233), (186, 233, 218)),
    "sand": ((253, 236, 214), (250, 226, 193)),
    "rose": ((254, 226, 226), (254, 205, 211)),
    "lilac": ((233, 228, 253), (221, 214, 254)),
}

SF = "/System/Library/Fonts/SFNSRounded.ttf"

# The app's floating tab bar sits over a scroll-edge material, and on a long
# scrolling screen the simulator captures the content behind it as a mirrored
# smear. It is a capture artifact rather than a bug, but it is unmistakable at
# store size, so those raws are cropped just above the tab bar. A screenshot
# without the tab bar is ordinary store creative; a screenshot with garbled
# text in it is not.
TAB_BAR_CROP = 210

# (raw, output, tint, headline, crop_bottom)
FRAMES = [
    ("02b-emergency.png", "store-1-emergency.png", "blue",
     "Everything a doctor\nasks for, on one screen",
     TAB_BAR_CROP),
    ("01-today.png", "store-2-today.png", "mint",
     "Know what was taken,\nand who marked it",
     TAB_BAR_CROP),
    ("03-detail.png", "store-3-medications.png", "blue",
     "One medication list,\nkept properly",
     TAB_BAR_CROP),
    ("04-tasks.png", "store-4-tasks.png", "sand",
     "Nobody calls the\npharmacy twice",
     TAB_BAR_CROP),
    ("05-timeline.png", "store-5-timeline.png", "lilac",
     "Two years of history,\nwithout the shoebox",
     TAB_BAR_CROP),
    # The paywall is a sheet: no tab bar, nothing to crop.
    ("07-paywall.png", "store-6-family.png", "rose",
     "Every feature free\nfor one person",
     0),
]


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def canvas(tint: str) -> Image.Image:
    top, bottom = TINTS[tint]
    image = Image.new("RGB", (W, H), top)
    draw = ImageDraw.Draw(image)
    for y in range(H):
        t = y / H
        draw.line(
            [(0, y), (W, y)],
            fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return image


def rounded(image: Image.Image, radius: int) -> Image.Image:
    """Rounds the corners of a screen capture so it sits inside the drawn body."""
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, image.size[0], image.size[1]], radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, max_width: int) -> list[str]:
    """Respects the author's own line breaks, then wraps anything still too wide."""
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words, current = paragraph.split(), ""
        for word in words:
            candidate = f"{current} {word}".strip()
            if draw.textlength(candidate, font=fnt) <= max_width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
    return lines


def compose(
    raw_name: str, out_name: str, tint: str, headline: str, crop_bottom: int = 0
) -> None:
    raw = Image.open(os.path.join(RAW, raw_name)).convert("RGB")
    if crop_bottom:
        raw = raw.crop((0, 0, raw.width, raw.height - crop_bottom))
    image = canvas(tint)
    draw = ImageDraw.Draw(image)

    margin = 84
    head_font = font(SF, 88)

    y = 150
    for line in wrap(draw, headline, head_font, W - margin * 2):
        draw.text((margin, y), line, font=head_font, fill=INK)
        y += 104

    # The phone. Scaled to whatever height is left, so a change to the copy
    # above cannot push the screen off the bottom of the canvas.
    top = y + 80
    bottom_margin = 90
    available_h = H - top - bottom_margin
    frame_w = W - margin * 2

    scale = min(frame_w / raw.width, available_h / raw.height)
    screen_w, screen_h = int(raw.width * scale), int(raw.height * scale)

    pad = 14
    body = [
        (W - screen_w) // 2 - pad, top - pad,
        (W - screen_w) // 2 + screen_w + pad, top + screen_h + pad,
    ]

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [body[0], body[1] + 16, body[2], body[3] + 16], 72, fill=(15, 23, 42, 70)
    )
    image.paste(
        Image.alpha_composite(image.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(26))).convert("RGB"),
        (0, 0),
    )

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(body, 72, fill=BEZEL)

    screen = rounded(raw.resize((screen_w, screen_h), Image.LANCZOS), 58)
    image.paste(screen, ((W - screen_w) // 2, top), screen)

    os.makedirs(OUT, exist_ok=True)
    image.save(os.path.join(OUT, out_name))
    print(f"  {out_name}  {image.size[0]}x{image.size[1]}")


def main() -> None:
    for args in FRAMES:
        compose(*args)
    print(f"==> {len(FRAMES)} screenshots in {OUT}")


if __name__ == "__main__":
    main()
