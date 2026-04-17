# ЗнатокOS — Кириллический шрифт для CC: Tweaked

Ресурспак Minecraft, заменяющий шрифт терминала CC: Tweaked на
Windows-1251-совместимый. Совместно с модулем `src/util/cyrillic.lua`
даёт корректное отображение кириллицы в ОС.

## Как это работает

CC: Tweaked рисует символы, индексируя их по байту (0–255). Кириллица
в исходниках на UTF-8 — двухбайтная. `cyrillic.lua` в рантайме
перекодирует все строки UTF-8 → CP1251 перед передачей в `term.write`,
а этот ресурспак кладёт кириллические глифы в позиции 0xA8, 0xB8,
0xC0–0xFF по Windows-1251.

## Установка

### 1. Сгенерировать шрифт

Нужен Python 3 с Pillow:

```
pip install pillow
python make_font.py
```

Скрипт соберёт `assets/computercraft/textures/gui/term_font.png`
размером 128×192 (16×16 ячеек по 8×12), с ASCII из стандартного шрифта
(если найдёт его рядом) и кириллицей, нарисованной из системного TTF
(Consolas / DejaVu Sans Mono / первый подходящий моно-шрифт с
кириллицей).

### 2. Упаковать в zip

```
zip -r znatokos-cyrillic.zip assets/ pack.mcmeta
```

### 3. Положить в Minecraft

```
%APPDATA%\.minecraft\resourcepacks\znatokos-cyrillic.zip
```

и включить в настройках → ресурспаки.

## Альтернатива: готовый шрифт из сообщества

Если лень возиться с генерацией, в интернете есть готовые
CC:Tweaked-совместимые кириллические шрифты. Положи их PNG по пути
`assets/computercraft/textures/gui/term_font.png` в этом
ресурспаке — и ОС будет читабельной.
