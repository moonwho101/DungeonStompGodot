"""Generate the project/export icons in res://icons/ from Assets/icon.png.

Assets/ is .gdignore'd, so Godot can't reference the source image directly.
Run from the repository root: python tools/generate_icons.py
"""

from pathlib import Path

from PIL import Image, ImageFilter, ImageOps, ImageEnhance

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets" / "icon.png"
OUT = ROOT / "icons"

# Android adaptive icons are 108dp with a 72dp visible area and a 66dp safe zone.
ADAPTIVE = 432
ADAPTIVE_SAFE = round(ADAPTIVE * 66 / 108)


def resized(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    src = Image.open(SRC).convert("RGBA")

    for size in (144, 180, 192, 256, 512):
        resized(src, size).save(OUT / f"icon_{size}.png", optimize=True)

    src.convert("RGB").save(
        OUT / "icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    offset = (ADAPTIVE - ADAPTIVE_SAFE) // 2
    fg = Image.new("RGBA", (ADAPTIVE, ADAPTIVE), (0, 0, 0, 0))
    fg.paste(resized(src, ADAPTIVE_SAFE), (offset, offset))
    fg.save(OUT / "icon_adaptive_foreground.png", optimize=True)

    bg = resized(src, ADAPTIVE).filter(ImageFilter.GaussianBlur(12))
    bg = ImageEnhance.Brightness(bg).enhance(0.45)
    bg.save(OUT / "icon_adaptive_background.png", optimize=True)

    # Themed (monochrome) icons only use the alpha channel; brightness keeps the glowing title visible.
    luma = ImageOps.autocontrast(resized(src, ADAPTIVE_SAFE).convert("L"))
    mono = Image.new("RGBA", (ADAPTIVE, ADAPTIVE), (255, 255, 255, 0))
    glyph = Image.new("RGBA", luma.size, (255, 255, 255, 255))
    glyph.putalpha(luma)
    mono.paste(glyph, (offset, offset))
    mono.save(OUT / "icon_adaptive_monochrome.png", optimize=True)

    print(f"Wrote icons to {OUT}")


if __name__ == "__main__":
    main()
