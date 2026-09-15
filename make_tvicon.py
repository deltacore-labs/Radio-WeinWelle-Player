#!/usr/bin/env python3
"""Generate tvOS layered app icon – official Radio Wein-Welle brand style."""

import os, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROJ     = os.path.dirname(os.path.abspath(__file__))
ASSETS   = os.path.join(PROJ, "Radio-WeinWelle-Player", "Assets.xcassets")
LOGO_SRC = os.path.join(ASSETS, "logo.imageset", "logo.png")
OUT      = os.path.join(ASSETS, "AppIcon-TV.brandassets")

# Official brand colors
NAVY_BG    = (13,  32,  73)     # #0D2049
NAVY_DARK  = (6,   16,  42)     # deeper edge
YELLOW     = (253, 200,   0)    # #FDC800
BLACK_TXT  = (22,  22,  22)
WHITE      = (255, 255, 255)

SIZES = [
    (400,  240,  "1x", "App Icon"),
    (800,  480,  "2x", "App Icon"),
    (1280, 768,  "1x", "App Icon - App Store"),
    (2560, 1536, "2x", "App Icon - App Store"),
]

# ── Helpers ──────────────────────────────────────────────────────────────────

def navy_gradient(w, h):
    x = np.linspace(0.0, 1.0, w, dtype=np.float32)
    y = np.linspace(0.0, 1.0, h, dtype=np.float32)
    xx, yy = np.meshgrid(x, y)
    t = xx * 0.45 + (1 - yy) * 0.55      # brighter upper-right
    r = np.clip(NAVY_DARK[0] + t * 22, 0, 40).astype(np.uint8)
    g = np.clip(NAVY_DARK[1] + t * 32, 0, 70).astype(np.uint8)
    b = np.clip(NAVY_DARK[2] + t * 58, 0, 130).astype(np.uint8)
    a = np.full((h, w), 255, dtype=np.uint8)
    return Image.fromarray(np.stack([r, g, b, a], axis=2), "RGBA")

def bold_font(size):
    candidates = [
        ("/System/Library/Fonts/HelveticaNeue.ttc",  size, 1),   # Bold face
        ("/System/Library/Fonts/Helvetica.ttc",       size, 1),
        ("/System/Library/Fonts/HelveticaNeue.ttc",  size, 0),
        ("/Library/Fonts/Arial Bold.ttf",             size, 0),
        ("/Library/Fonts/Arial.ttf",                  size, 0),
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
    ImageDraw.Draw(mask).ellipse((2, 2, size-2, size-2), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=max(1, size // 60)))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(logo, mask=mask)
    return out

# ── Logo mark: red circle + yellow pill ──────────────────────────────────────

def fit_font(text, max_w, sz_max, sz_min=10):
    """Return a font sized so `text` fits within max_w pixels."""
    sz = sz_max
    while sz >= sz_min:
        f = bold_font(sz)
        bb = f.getbbox(text)
        if (bb[2] - bb[0]) <= max_w:
            return f, sz
        sz = max(sz_min, int(sz * 0.92))
    return bold_font(sz_min), sz_min

def logo_mark(icon_h):
    """Build the combined official logo mark at the given height."""
    circ_d  = int(icon_h * 0.70)   # circle = 70 % of icon height
    pill_h  = int(circ_d * 0.72)   # pill height
    overlap = int(circ_d * 0.33)   # circle→pill overlap

    # Try pill widths until the mark fits within icon_w = icon_h * 4/3
    max_mark_w = int(icon_h * 1.55)   # generous budget for a 16:9 canvas
    for pill_ratio in (2.55, 2.35, 2.15, 2.0, 1.85):
        pill_w = int(pill_h * pill_ratio)
        mw = circ_d - overlap + pill_w
        if mw <= max_mark_w:
            break

    mh = max(circ_d, pill_h)
    mark = Image.new("RGBA", (mw, mh), (0, 0, 0, 0))
    draw  = ImageDraw.Draw(mark)

    # Yellow pill
    px  = circ_d - overlap
    py  = (mh - pill_h) // 2
    rad = pill_h // 2
    draw.rounded_rectangle((px, py, px + pill_w, py + pill_h),
                            radius=rad, fill=(*YELLOW, 255))

    # Text region: visible part of pill (to the right of the circle)
    h_pad = int(pill_h * 0.07)
    v_pad = int(pill_h * 0.09)
    txt_x0 = px + overlap + h_pad
    txt_w  = pill_w - overlap - 2 * h_pad
    cx     = txt_x0 + txt_w // 2

    fr, _ = fit_font("RADIO",      int(txt_w * 0.96), int(pill_h * 0.44))
    fw, _ = fit_font("WEIN-WELLE", int(txt_w * 0.96), int(pill_h * 0.28))

    draw.text((cx, py + int(pill_h * 0.29)), "RADIO",
              font=fr, fill=(*BLACK_TXT, 255), anchor="mm")
    draw.text((cx, py + int(pill_h * 0.74)), "WEIN-WELLE",
              font=fw, fill=(*BLACK_TXT, 255), anchor="mm")

    # Paste red circle on top (covers left pill edge)
    circ = circle_logo(circ_d)
    mark.paste(circ, (0, (mh - circ_d) // 2), circ)

    return mark

# ── Decorative curved lines ───────────────────────────────────────────────────

def add_curves(base):
    w, h = base.size
    ov = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(ov)
    n = 14
    for i in range(n):
        alpha = max(0, int(50 - i * 3.2))
        r = int(w * (0.38 + i * 0.065))
        cx = int(w * 1.08)
        cy = int(h * -0.08)
        lw = max(1, int(w * 0.0018))
        draw.arc((cx-r, cy-r, cx+r, cy+r), start=162, end=228,
                 fill=(255, 255, 255, alpha), width=lw)
    return Image.alpha_composite(base, ov)

# ── Three layers ──────────────────────────────────────────────────────────────

def back_layer(w, h):
    return add_curves(navy_gradient(w, h))

def middle_layer(w, h):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    mark = logo_mark(h)
    mw, mh = mark.size

    # Center mark, nudged slightly up
    mx = (w - mw) // 2
    my = (h - mh) // 2 - int(h * 0.025)

    # Drop shadow
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh_src = Image.new("RGBA", (mw, mh), (0, 0, 0, 0))
    sh_src.paste(Image.new("RGBA", (mw, mh), (0, 0, 0, 130)),
                 mask=mark.getchannel("A"))
    sh.paste(sh_src, (mx + int(h * 0.012), my + int(h * 0.018)))
    sh = sh.filter(ImageFilter.GaussianBlur(radius=int(h * 0.028)))
    layer = Image.alpha_composite(layer, sh)

    layer.paste(mark, (mx, my), mark)
    return layer

def front_layer(w, h):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw  = ImageDraw.Draw(layer)

    f1 = bold_font(int(h * 0.057))
    f2 = bold_font(int(h * 0.036))
    cx = w // 2
    y1 = int(h * 0.815)
    y2 = int(h * 0.876)

    draw.text((cx, y1), "DAS WINZERFESTRADIO",
              font=f1, fill=(255, 255, 255, 215), anchor="mm")
    draw.text((cx, y2), "AUS GROSS-UMSTADT FÜR DIE REGION",
              font=f2, fill=(180, 205, 235, 155), anchor="mm")
    return layer

# ── Output helpers ────────────────────────────────────────────────────────────

def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print(f"    {os.path.basename(path)}  {img.width}×{img.height}")

def wjson(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

INFO = {"author": "xcode", "version": 1}

def main():
    print("Generating tvOS icon (official brand style)…\n")

    by_set: dict[str, list] = {}
    for w, h, scale, sname in SIZES:
        by_set.setdefault(sname, []).append((w, h, scale))

    brandassets_images = []

    for sname, entries in by_set.items():
        print(f"  {sname}")
        stack_dir = os.path.join(OUT, f"{sname}.imagestack")
        layer_imgs: dict[str, list] = {"Back": [], "Middle": [], "Front": []}

        for w, h, scale in entries:
            tag = f"{w}x{h}"
            print(f"  {scale}  ({w}×{h})")
            save(back_layer(w, h),   os.path.join(stack_dir, "Back.imagestacklayer",   "Content.imageset", f"back_{tag}.png"))
            save(middle_layer(w, h), os.path.join(stack_dir, "Middle.imagestacklayer", "Content.imageset", f"mid_{tag}.png"))
            save(front_layer(w, h),  os.path.join(stack_dir, "Front.imagestacklayer",  "Content.imageset", f"front_{tag}.png"))
            layer_imgs["Back"].append(  (scale, f"back_{tag}.png"))
            layer_imgs["Middle"].append((scale, f"mid_{tag}.png"))
            layer_imgs["Front"].append( (scale, f"front_{tag}.png"))

        for lname, imgs in layer_imgs.items():
            ld = os.path.join(stack_dir, f"{lname}.imagestacklayer")
            wjson(os.path.join(ld, "Contents.json"),
                  {"info": INFO, "layers": [{"filename": "Content.imageset"}]})
            wjson(os.path.join(ld, "Content.imageset", "Contents.json"),
                  {"info": INFO,
                   "images": [{"filename": fn, "idiom": "tv", "scale": sc}
                               for sc, fn in imgs]})

        wjson(os.path.join(stack_dir, "Contents.json"),
              {"info": INFO, "layers": [
                  {"filename": "Front.imagestacklayer"},
                  {"filename": "Middle.imagestacklayer"},
                  {"filename": "Back.imagestacklayer"},
              ]})
        brandassets_images.append({"filename": f"{sname}.imagestack", "idiom": "tv"})

    wjson(os.path.join(OUT, "Contents.json"),
          {"info": INFO, "images": brandassets_images})
    print(f"\n✓  {OUT}")

if __name__ == "__main__":
    main()
