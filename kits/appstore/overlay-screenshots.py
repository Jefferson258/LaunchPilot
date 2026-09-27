#!/usr/bin/env python3
"""Build promotional App Store screenshots: branded canvas + headline + device shot.

Reads originals from screenshots/raw/ (backs up from screenshots/ on first run),
writes marketing PNGs into screenshots/ for ASC upload.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent

COPY = {
    "velour": {
        "01-home.png": ("Your closet, curated", "Photograph pieces · plan looks · all on iPad"),
        "02-closet.png": ("Every piece, organized", "Browse by category, color, and vibe"),
        "03-closet-filter.png": ("Find it in a tap", "Filter your wardrobe without the dig"),
        "04-item-detail.png": ("Rich item cards", "Tags, photos, and details that stick"),
        "05-today.png": ("Swipe today’s outfit", "Mix tops, bottoms, shoes — then log it"),
        "06-calendar.png": ("Your outfit history", "See what you wore, day by day"),
    },
    "corvim": {
        "01-home.png": ("Train smarter", "Schedule, start, or get a recommended workout"),
        "02-workout.png": ("Jump in or follow a plan", "Quick start · saved routines · form-aware cardio"),
        "03-progress.png": ("See the work add up", "Sessions, trends, and what you actually lifted"),
        "04-social.png": ("Train with friends", "Share finished workouts and cheer each other on"),
        "05-groups.png": ("Team training", "Groups, invites, and coaching in one place"),
    },
    "juicd": {
        "01-play.png": ("Build picks in seconds", "Virtual points only — no real-money wagering"),
        "02-parlay.png": ("Mix picks your way", "Stack legs with virtual points — entertainment only"),
        "03-tourney.png": ("Daily closest-pick tourneys", "One bracket a day. Closest wins. Zero stake."),
        "04-dashboard.png": ("Track your climb", "Rank, momentum, and season progress"),
        "05-friends.png": ("Climb with your crew", "Compare leaderboards with friends"),
        "06-profile.png": ("Your season, at a glance", "Stats, tiers, and how you’re trending"),
    },
}

# Canvas colors + text (RGB)
THEMES = {
    "velour": {
        "bg_top": (255, 228, 236),
        "bg_bot": (245, 210, 222),
        "headline": (88, 28, 52),
        "sub": (130, 70, 95),
        "accent": (190, 70, 110),
        "frame": (255, 255, 255),
    },
    "corvim": {
        "bg_top": (14, 20, 22),
        "bg_bot": (28, 40, 38),
        "headline": (210, 250, 235),
        "sub": (160, 190, 180),
        "accent": (90, 210, 170),
        "frame": (30, 36, 38),
    },
    "juicd": {
        "bg_top": (8, 12, 22),
        "bg_bot": (18, 28, 48),
        "headline": (235, 242, 255),
        "sub": (150, 180, 220),
        "accent": (70, 160, 255),
        "frame": (20, 26, 40),
    },
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
    shots = ROOT / "products" / app / "screenshots"
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
    theme = THEMES[app]
    headline, subline = COPY[app][name]
    shot = Image.open(src).convert("RGB")
    # Target ASC sizes
    if app == "velour":
        canvas_size = (2064, 2752)
    else:
        canvas_size = (1290, 2796)

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

    h_size = int(cw * (0.062 if app == "velour" else 0.078))
    s_size = int(cw * (0.030 if app == "velour" else 0.038))
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
    for app, files in COPY.items():
        raw = ensure_raw(app)
        out_dir = ROOT / "products" / app / "screenshots"
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
