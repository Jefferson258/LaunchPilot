#!/usr/bin/env python3
"""Build promotional App Store screenshots: branded canvas + headline + device shot.

Usage: python3 overlay-screenshots.py [app-key ...]   (default: every app with "overlay")

Reads originals from screenshots/raw/ (backs up from screenshots/ on first run),
writes marketing PNGs into screenshots/ for ASC upload.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent

# Per-app headline copy, colors and canvas size live in the gitignored
# apps.local.json under each app's "overlay" key (see apps.example.json).
from _apps import load_apps  # noqa: E402

DEFAULT_THEME = {
    "bg_top": (14, 20, 30),
    "bg_bot": (30, 40, 60),
    "headline": (240, 244, 255),
    "sub": (170, 185, 210),
    "accent": (90, 150, 255),
    "frame": (30, 36, 48),
}
DEFAULT_CANVAS = (1290, 2796)  # iPhone 6.7"; iPad 12.9" is (2064, 2752)


def overlay_cfg(app: str) -> dict:
    cfg = load_apps()[app].get("overlay") or {}
    theme = {**DEFAULT_THEME, **{k: tuple(v) for k, v in (cfg.get("theme") or {}).items()}}
    return {
        "copy": {k: tuple(v) for k, v in (cfg.get("copy") or {}).items()},
        "theme": theme,
        "canvas": tuple(cfg.get("canvas") or DEFAULT_CANVAS),
        "headline_scale": float(cfg.get("headline_scale", 0.078)),
        "sub_scale": float(cfg.get("sub_scale", 0.038)),
    }


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    paths = (
        [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/Library/Fonts/Arial Bold.ttf",
        ]
        if bold
        else [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/Library/Fonts/Arial.ttf",
        ]
    )
    for path in paths:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def ensure_raw(app: str) -> Path:
    shots = load_apps()[app]["dir"] / "screenshots"
    raw = shots / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    # Prefer restoring from raw if overlays already overwrote screenshots/
    for src in sorted(shots.glob("*.png")):
        if src.name.endswith(".asc.png"):
            continue
        dest = raw / src.name
        if not dest.exists():
            shutil.copy2(src, dest)
    return raw


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.ImageFont, max_w: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def gradient(size: tuple[int, int], top: tuple[int, int, int], bot: tuple[int, int, int]) -> Image.Image:
    w, h = size
    im = Image.new("RGB", size)
    px = im.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return im


def rounded_device(shot: Image.Image, radius: int) -> Image.Image:
    shot = shot.convert("RGBA")
    mask = Image.new("L", shot.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), radius=radius, fill=255)
    out = Image.new("RGBA", shot.size, (0, 0, 0, 0))
    out.paste(shot, (0, 0))
    out.putalpha(mask)
    return out


def compose(app: str, name: str, src: Path, dest: Path) -> None:
    oc = overlay_cfg(app)
    theme = oc["theme"]
    headline, subline = oc["copy"][name]
    shot = Image.open(src).convert("RGB")
    canvas_size = oc["canvas"]

    canvas = gradient(canvas_size, theme["bg_top"], theme["bg_bot"])
    draw = ImageDraw.Draw(canvas)
    cw, ch = canvas_size

    pad_x = int(cw * 0.07)
    max_text = cw - pad_x * 2
    y = int(ch * 0.055)

    # Accent bar
    draw.rounded_rectangle(
        (pad_x, y, pad_x + int(cw * 0.12), y + max(6, ch // 350)),
        radius=4,
        fill=theme["accent"],
    )
    y += int(ch * 0.025)

    h_size = int(cw * oc["headline_scale"])
    s_size = int(cw * oc["sub_scale"])
    hf = font(h_size, bold=True)
    sf = font(s_size, bold=False)

    for line in wrap(draw, headline, hf, max_text):
        draw.text((pad_x, y), line, font=hf, fill=theme["headline"])
        y += int(h_size * 1.15)
    y += int(ch * 0.008)
    for line in wrap(draw, subline, sf, max_text):
        draw.text((pad_x, y), line, font=sf, fill=theme["sub"])
        y += int(s_size * 1.3)

    text_bottom = y + int(ch * 0.02)

    # Device frame area
    margin_x = int(cw * 0.08)
    margin_bot = int(ch * 0.04)
    avail_w = cw - margin_x * 2
    avail_h = ch - text_bottom - margin_bot

    scale = min(avail_w / shot.width, avail_h / shot.height)
    dw = int(shot.width * scale)
    dh = int(shot.height * scale)
    device = shot.resize((dw, dh), Image.Resampling.LANCZOS)

    radius = max(28, int(min(dw, dh) * 0.045))
    framed = rounded_device(device, radius)

    # Soft drop shadow
    shadow = Image.new("RGBA", (dw + 40, dh + 40), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((20, 24, 20 + dw, 24 + dh), radius=radius, fill=(0, 0, 0, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))

    dx = (cw - dw) // 2
    dy = text_bottom + (avail_h - dh) // 2

    base = canvas.convert("RGBA")
    base.alpha_composite(shadow, (dx - 20, dy - 16))
    base.alpha_composite(framed, (dx, dy))

    # Thin frame ring
    ring = ImageDraw.Draw(base)
    ring.rounded_rectangle(
        (dx - 2, dy - 2, dx + dw + 1, dy + dh + 1),
        radius=radius + 2,
        outline=(*theme["frame"], 255),
        width=max(3, cw // 400),
    )

    dest.parent.mkdir(parents=True, exist_ok=True)
    base.convert("RGB").save(dest, format="PNG", optimize=True)


def main() -> None:
    import sys

    apps = load_apps()
    keys = sys.argv[1:] or [k for k, v in apps.items() if v.get("overlay")]
    for app in keys:
        files = overlay_cfg(app)["copy"]
        if not files:
            print(f"  skip {app}: no overlay.copy configured")
            continue
        raw = ensure_raw(app)
        out_dir = apps[app]["dir"] / "screenshots"
        for name in files:
            src = raw / name
            if not src.exists():
                print(f"  skip missing {app}/{name}")
                continue
            # If raw was polluted by a previous overlay pass, detect by checking
            # whether raw looks like a marketing canvas (has huge letterboxing).
            # Prefer raw always — first run copied clean originals.
            print(f"  compose {app}/{name}")
            compose(app, name, src, out_dir / name)
    print("done")


if __name__ == "__main__":
    main()
