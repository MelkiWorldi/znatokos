#!/usr/bin/env python3
"""
Генератор term_font.png для ЗнатокOS / CC: Tweaked.

Собирает 128×192 PNG шрифта (16×16 ячеек по 8×12):
- ASCII (0x00-0x7F) копируется из стандартного шрифта CC, если он
  найден в /rom/ или указан через --base.
- Кириллица в позициях CP1251 (0xA8, 0xB8, 0xC0-0xFF) рисуется
  из системного TTF (Consolas / DejaVu Sans Mono / любой моно-шрифт
  с кириллицей).

Использование:
    python make_font.py
    python make_font.py --base path/to/original_term_font.png --font consola.ttf

Требует: pip install pillow
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Нужен Pillow: pip install pillow", file=sys.stderr)
    sys.exit(1)

CELL_W, CELL_H = 8, 11           # FONT_WIDTH+2, FONT_HEIGHT+2
GRID = 16
IMG_W, IMG_H = 256, 256          # фиксированный размер текстуры в CC:Tweaked
GLYPH_W, GLYPH_H = 6, 9
GLYPH_OFF = (1, 1)

# Позиции в CP1251, которые мы будем рисовать.
# Ё, ё плюс диапазон А..я.
CP1251_CHARS: dict[int, str] = {}
for i in range(0x0410, 0x0450):        # А..я
    CP1251_CHARS[i - 0x0410 + 0xC0] = chr(i)
CP1251_CHARS[0xA8] = "Ё"
CP1251_CHARS[0xB8] = "ё"
CP1251_CHARS[0xB9] = "№"

# Кандидаты шрифтов на Windows / Linux / macOS.
FONT_CANDIDATES = [
    "consola.ttf",
    "C:/Windows/Fonts/consola.ttf",
    "C:/Windows/Fonts/cour.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "DejaVuSansMono.ttf",
]


def load_system_font(explicit: str | None) -> ImageFont.FreeTypeFont:
    candidates = [explicit] if explicit else FONT_CANDIDATES
    for name in candidates:
        if not name:
            continue
        try:
            return ImageFont.truetype(name, GLYPH_H)
        except (OSError, IOError):
            continue
    raise FileNotFoundError(
        "Не удалось найти моно-шрифт с кириллицей. "
        "Укажите --font путь/к/шрифту.ttf"
    )


def blit_ascii_base(img: Image.Image, base_path: Path | None) -> None:
    """Копирует ASCII (0x00-0x7F) глифы из переданного PNG стандартного шрифта."""
    if not base_path or not base_path.exists():
        print("Базовый шрифт не указан — ASCII придётся нарисовать из TTF.")
        return
    base = Image.open(base_path).convert("RGBA")
    if base.size != (IMG_W, IMG_H):
        print(f"Внимание: {base_path} имеет размер {base.size}, "
              f"ожидалось {(IMG_W, IMG_H)}. Копируем первую половину как есть.")
    # Копируем первые 8 строк (0x00-0x7F).
    for code in range(0, 0x80):
        cx, cy = (code % GRID) * CELL_W, (code // GRID) * CELL_H
        box = (cx, cy, cx + CELL_W, cy + CELL_H)
        cell = base.crop(box)
        img.paste(cell, box)


def draw_glyphs(img: Image.Image, font: ImageFont.FreeTypeFont,
                chars: dict[int, str], draw_ascii_fallback: bool = True) -> None:
    draw = ImageDraw.Draw(img)
    all_codes = dict(chars)
    if draw_ascii_fallback:
        for c in range(0x20, 0x7F):
            all_codes.setdefault(c, chr(c))
    for code, ch in all_codes.items():
        cx = (code % GRID) * CELL_W + GLYPH_OFF[0]
        cy = (code // GRID) * CELL_H + GLYPH_OFF[1]
        draw.text((cx, cy - 1), ch, font=font, fill=(255, 255, 255, 255))


def clear_cells(img: Image.Image, codes) -> None:
    """Стирает ячейки (делает их прозрачными) перед отрисовкой новых глифов."""
    for code in codes:
        cx, cy = (code % GRID) * CELL_W, (code // GRID) * CELL_H
        for x in range(cx, cx + CELL_W):
            for y in range(cy, cy + CELL_H):
                img.putpixel((x, y), (0, 0, 0, 0))


def main() -> None:
    p = argparse.ArgumentParser(description="Сгенерировать кириллический term_font.png")
    p.add_argument("--base", type=Path,
                   default=Path("original_term_font.png"),
                   help="исходный term_font.png (ASCII)")
    p.add_argument("--font", type=str, help="путь к моно-TTF с кириллицей")
    p.add_argument("--size", type=int, default=8, help="размер TTF в пунктах")
    p.add_argument("--out", type=Path,
                   default=Path("assets/computercraft/textures/gui/term_font.png"))
    args = p.parse_args()

    if args.base and args.base.exists():
        img = Image.open(args.base).convert("RGBA")
        if img.size != (IMG_W, IMG_H):
            raise ValueError(f"base font {img.size} != {(IMG_W, IMG_H)}")
        clear_cells(img, CP1251_CHARS.keys())
        print(f"Основа: {args.base}  ({img.size[0]}×{img.size[1]})")
    else:
        img = Image.new("RGBA", (IMG_W, IMG_H), (0, 0, 0, 0))
        print("Основа: пустая")

    # Пытаемся использовать ручные битмапы
    try:
        from cyrillic_bitmaps import GLYPHS
        print(f"Используем ручные битмапы: {len(GLYPHS)} глифов")
    except ImportError:
        GLYPHS = {}

    white = (255, 255, 255, 255)
    drawn = 0
    ttf_fallback_chars: dict[int, str] = {}

    for code, ch in CP1251_CHARS.items():
        bitmap = GLYPHS.get(ch)
        if bitmap:
            cx = (code % GRID) * CELL_W + GLYPH_OFF[0]
            cy = (code // GRID) * CELL_H + GLYPH_OFF[1]
            for y, row in enumerate(bitmap):
                for x, pix in enumerate(row):
                    if pix == "#":
                        img.putpixel((cx + x, cy + y), white)
            drawn += 1
        else:
            ttf_fallback_chars[code] = ch

    # Остальные символы (если есть) — через TTF без AA
    if ttf_fallback_chars:
        font = ImageFont.truetype(
            args.font or next(
                (p for p in FONT_CANDIDATES if p and _try_path(p)),
                None) or FONT_CANDIDATES[0],
            args.size,
        )
        draw = ImageDraw.Draw(img)
        draw.fontmode = "1"
        for code, ch in ttf_fallback_chars.items():
            cx = (code % GRID) * CELL_W + GLYPH_OFF[0]
            cy = (code // GRID) * CELL_H + GLYPH_OFF[1]
            draw.text((cx, cy - 1), ch, font=font, fill=white)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    img.save(args.out)
    print(f"Записан {args.out}  ({IMG_W}×{IMG_H})")
    print(f"Нарисовано битмапами: {drawn}, из TTF: {len(ttf_fallback_chars)}")


def _try_path(p: str) -> bool:
    try:
        ImageFont.truetype(p, 8)
        return True
    except (OSError, IOError):
        return False


if __name__ == "__main__":
    main()
