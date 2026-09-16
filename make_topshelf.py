#!/usr/bin/env python3
"""Generate tvOS Top Shelf Wide image – official Radio Wein-Welle brand style.

Output: Assets.xcassets/TopShelfImageWide.imageset/
  TopShelfImageWide_1x.png  2320×720
  TopShelfImageWide_2x.png  4640×1440
"""

import os, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROJ     = os.path.dirname(os.path.abspath(__file__))
ASSETS   = os.path.join(PROJ, "Radio-WeinWelle-Player", "Assets.xcassets")
LOGO_SRC = os.path.join(ASSETS, "logo.imageset", "logo.png")
OUT      = os.path.join(ASSETS, "TopShelfImageWide.imageset")

NAVY_BG   = (13,  32,  73)
NAVY_DARK = (6,   16,  42)
YELLOW    = (253, 200,   0)
BLACK_TXT = (22,  22,  22)
WHITE     = (255, 255, 255)

SIZES = [
    (2320, 720,  "1x", "TopShelfImageWide_1x.png"),
    (4640, 1440, "2x", "TopShelfImageWide_2x.png"),
]


def navy_gradient(w, h):
    x = np.linspace(0.0, 1.0, w, dtype=np.float32)
    y = np.linspace(0.0, 1.0, h, dtype=np.float32)
    xx, yy = np.meshgrid(x, y)
    t = xx * 0.55 + (1 - yy) * 0.45
    r = np.clip(NAVY_DARK[0] + t * 22, 0, 40).astype(np.uint8)
    g = np.clip(NAVY_DARK[1] + t * 32, 0, 70).astype(np.uint8)
    b = np.clip(NAVY_DARK[2] + t * 60, 0, 130).astype(np.uint8)
    a = np.full((h, w), 255, dtype=np.uint8)
    return Image.fromarray(np.stack([r, g, b, a], axis=2), "RGBA")


def bold_font(size):
    candidates = [
        ("/System/Library/Fonts/HelveticaNeue.ttc", size, 1),
        ("/System/Library/Fonts/Helvetica.ttc",      size, 1),
        ("/System/Library/Fonts/HelveticaNeue.ttc", size, 0),
        ("/Library/Fonts/Arial Bold.ttf",            size, 0),
        ("/Library/Fonts/Arial.ttf",                 size, 0),
    ]
    for path, sz, idx in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, sz, index=idx)
            except Exception:
                pass
    return ImageFont.load_default(size=size)


def circle_logo(size):
    logo = Image.open(LOGO_SRC).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((2, 2, size - 2, size - 2), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=max(1, size // 60)))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(logo, mask=mask)
    return out


def fit_font(text, max_w, sz_max, sz_min=10):
    sz = sz_max
    while sz >= sz_min:
        f = bold_font(sz)
        bb = f.getbbox(text)
        if (bb[2] - bb[0]) <= max_w:
            return f, sz
        sz = max(sz_min, int(sz * 0.92))
    return bold_font(sz_min), sz_min


def add_curves(base):
    w, h = base.size
    ov = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(ov)
    n = 18
    for i in range(n):
        alpha = max(0, int(45 - i * 2.4))
        r = int(w * (0.22 + i * 0.038))
        cx = int(w * 1.06)
        cy = int(h * -0.10)
        lw = max(1, int(h * 0.003))
        draw.arc((cx - r, cy - r, cx + r, cy + r), start=165, end=225,
                 fill=(255, 255, 255, alpha), width=lw)
    return Image.alpha_composite(base, ov)


def build_image(w, h):
    base = add_curves(navy_gradient(w, h))

    # --- logo mark (circle + pill) ---
    icon_h = int(h * 0.58)
    circ_d = int(icon_h * 0.70)
    pill_h = int(circ_d * 0.72)
    overlap = int(circ_d * 0.33)
    pill_w = int(pill_h * 2.55)

    mw = circ_d - overlap + pill_w
    mh = max(circ_d, pill_h)
    mark = Image.new("RGBA", (mw, mh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mark)

    px = circ_d - overlap
    py = (mh - pill_h) // 2
    rad = pill_h // 2
    draw.rounded_rectangle((px, py, px + pill_w, py + pill_h),
                            radius=rad, fill=(*YELLOW, 255))

    h_pad = int(pill_h * 0.07)
    txt_w = pill_w - overlap - 2 * h_pad
    txt_x0 = px + overlap + h_pad
    cx_pill = txt_x0 + txt_w // 2

    fr, _ = fit_font("RADIO",      int(txt_w * 0.96), int(pill_h * 0.44))
    fw, _ = fit_font("WEIN-WELLE", int(txt_w * 0.96), int(pill_h * 0.28))
    draw.text((cx_pill, py + int(pill_h * 0.29)), "RADIO",
              font=fr, fill=(*BLACK_TXT, 255), anchor="mm")
    draw.text((cx_pill, py + int(pill_h * 0.74)), "WEIN-WELLE",
              font=fw, fill=(*BLACK_TXT, 255), anchor="mm")

    mark.paste(circle_logo(circ_d), (0, (mh - circ_d) // 2), circle_logo(circ_d))

    # drop shadow
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh_src = Image.new("RGBA", (mw, mh), (0, 0, 0, 0))
    sh_src.paste(Image.new("RGBA", (mw, mh), (0, 0, 0, 120)),
                 mask=mark.getchannel("A"))
    mx = (w - mw) // 2
    my = (h - mh) // 2 - int(h * 0.04)
    sh.paste(sh_src, (mx + int(h * 0.012), my + int(h * 0.018)))
    sh = sh.filter(ImageFilter.GaussianBlur(radius=int(h * 0.025)))
    base = Image.alpha_composite(base, sh)
    base.paste(mark, (mx, my), mark)

    # --- tagline ---
    draw2 = ImageDraw.Draw(base)
    f1 = bold_font(int(h * 0.072))
    f2 = bold_font(int(h * 0.045))
    cx = w // 2
    draw2.text((cx, int(h * 0.808)), "DAS WINZERFESTRADIO",
               font=f1, fill=(255, 255, 255, 220), anchor="mm")
    draw2.text((cx, int(h * 0.878)), "AUS GROSS-UMSTADT FÜR DIE REGION",
               font=f2, fill=(180, 205, 235, 160), anchor="mm")

    return base.convert("RGB")


def main():
    print("Generating tvOS Top Shelf Wide image…\n")
    os.makedirs(OUT, exist_ok=True)

    images_json = []
    for w, h, scale, fname in SIZES:
        print(f"  {scale}  ({w}×{h})")
        img = build_image(w, h)
        path = os.path.join(OUT, fname)
        img.save(path, "PNG")
        print(f"    → {fname}")
        images_json.append({"filename": fname, "idiom": "tv", "scale": scale})

    contents = {"info": {"author": "xcode", "version": 1}, "images": images_json}
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print(f"\n✓  {OUT}")


if __name__ == "__main__":
    main()
