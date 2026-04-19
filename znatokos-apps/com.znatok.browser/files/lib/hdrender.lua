-- lib/hdrender.lua — HD-рендерер страницы для HDMonitor (Day 7).
--
-- В отличие от render.lua (работает через term на 16-цветном CC-мониторе),
-- hdrender.lua рисует боксы layout'а прямо в пиксельный framebuffer HDMonitor'а,
-- используя true-color RGB и произвольный scale шрифта.
--
-- API:
--   M.init(hdmon, theme, opts)
--     hdmon        peripheral.wrap("hdmonitor_N")
--     theme        таблица цветов (см. themes/default.lua), hex или colors.*
--     opts.scale   целочисленный scale шрифта (1..4), default 1
--     opts.charPx  ширина символа в пикселях при scale=1 (обычно 8)
--     opts.linePx  высота строки в пикселях при scale=1 (обычно 12)
--
--   M.size()             -> pxW, pxH
--   M.charsPerLine()     -> сколько символов помещается в ширину
--   M.clear([r,g,b])     заливка.
--   M.drawPage(boxes, scrollY, viewport)  отрисовка набора боксов
--   M.flush()            вызвать hdmon.flush() (если setAutoFlush(false))
--   M.hitTest(boxes, pxX, pxY, scrollY, viewport) -> box

local M = {}

-- Состояние модуля (одна активная HD-сессия).
local S = {
    dev     = nil,
    theme   = {},
    scale   = 1,
    charPx  = 8,
    linePx  = 12,
    pxW     = 0,
    pxH     = 0,
    autoFlush = true,
}

-- ---------------------------------------------------------------
-- Цвета
-- ---------------------------------------------------------------

-- Таблица CC colors → RGB (те же значения, что CC palette по умолчанию).
local CC_TO_RGB = {
    [colors.white]      = {0xF0, 0xF0, 0xF0},
    [colors.orange]     = {0xF2, 0xB2, 0x33},
    [colors.magenta]    = {0xE5, 0x7F, 0xD8},
    [colors.lightBlue]  = {0x99, 0xB2, 0xF2},
    [colors.yellow]     = {0xDE, 0xDE, 0x6C},
    [colors.lime]       = {0x7F, 0xCC, 0x19},
    [colors.pink]       = {0xF2, 0xB2, 0xCC},
    [colors.gray]       = {0x4C, 0x4C, 0x4C},
    [colors.lightGray]  = {0x99, 0x99, 0x99},
    [colors.cyan]       = {0x4C, 0x99, 0xB2},
    [colors.purple]     = {0xB2, 0x66, 0xE5},
    [colors.blue]       = {0x33, 0x66, 0xCC},
    [colors.brown]      = {0x7F, 0x66, 0x4C},
    [colors.green]      = {0x57, 0xA6, 0x4E},
    [colors.red]        = {0xCC, 0x4C, 0x4C},
    [colors.black]      = {0x11, 0x11, 0x11},
}

-- Принимает:
--   число (CC colors) -> RGB
--   строку "#RRGGBB" или "#RGB"
--   таблицу {r,g,b}
-- Возвращает r,g,b (0..255).
local function toRgb(c, fallback)
    fallback = fallback or {0, 0, 0}
    if c == nil then return fallback[1], fallback[2], fallback[3] end
    if type(c) == "table" then
        return c[1] or 0, c[2] or 0, c[3] or 0
    end
    if type(c) == "number" then
        local t = CC_TO_RGB[c]
        if t then return t[1], t[2], t[3] end
        return fallback[1], fallback[2], fallback[3]
    end
    if type(c) == "string" then
        local s = c:gsub("#", "")
        if #s == 3 then
            local r = tonumber(s:sub(1,1), 16) or 0
            local g = tonumber(s:sub(2,2), 16) or 0
            local b = tonumber(s:sub(3,3), 16) or 0
            return r * 17, g * 17, b * 17
        elseif #s == 6 then
            local r = tonumber(s:sub(1,2), 16) or 0
            local g = tonumber(s:sub(3,4), 16) or 0
            local b = tonumber(s:sub(5,6), 16) or 0
            return r, g, b
        end
    end
    return fallback[1], fallback[2], fallback[3]
end

M.toRgb = toRgb

-- ---------------------------------------------------------------
-- Init / size
-- ---------------------------------------------------------------

function M.init(hdmon, theme, opts)
    opts = opts or {}
    S.dev     = hdmon
    S.theme   = theme or {}
    S.scale   = math.max(1, math.min(4, opts.scale or 1))
    S.charPx  = opts.charPx or 8
    S.linePx  = opts.linePx or 12
    if hdmon and hdmon.getSize then
        local ok, w, h = pcall(hdmon.getSize)
        if ok then S.pxW, S.pxH = w or 0, h or 0 end
    end
    -- Батчевой режим для быстрой перерисовки.
    if hdmon and hdmon.setAutoFlush then
        pcall(hdmon.setAutoFlush, false)
        S.autoFlush = false
    end
    return S
end

function M.size() return S.pxW, S.pxH end
function M.scale() return S.scale end

-- Сколько символов помещается в одну "строку" HD-рендера.
function M.charsPerLine()
    if S.pxW == 0 then return 0 end
    return math.floor(S.pxW / (S.charPx * S.scale))
end

function M.linesPerScreen()
    if S.pxH == 0 then return 0 end
    return math.floor(S.pxH / (S.linePx * S.scale))
end

-- ---------------------------------------------------------------
-- Низкоуровневые wrap'ы (на случай если device отсутствует)
-- ---------------------------------------------------------------

local function dev() return S.dev end

function M.clear(r, g, b)
    local d = dev(); if not d or not d.clear then return end
    r = r or 0; g = g or 0; b = b or 0
    pcall(d.clear, r, g, b)
end

function M.drawRect(x, y, w, h, r, g, b)
    local d = dev(); if not d or not d.drawRect then return end
    if w <= 0 or h <= 0 then return end
    pcall(d.drawRect, x, y, w, h, r, g, b)
end

function M.drawText(x, y, text, r, g, b, scale)
    local d = dev(); if not d or not d.drawText then return end
    pcall(d.drawText, x, y, tostring(text or ""), r, g, b, scale or S.scale)
end

function M.drawImage(x, y, w, h, rgbBytes)
    local d = dev(); if not d or not d.drawImage then return end
    if not rgbBytes or #rgbBytes ~= w * h * 3 then return end
    pcall(d.drawImage, x, y, w, h, rgbBytes)
end

function M.flush()
    local d = dev()
    if d and d.flush and not S.autoFlush then pcall(d.flush) end
end

-- ---------------------------------------------------------------
-- Координатный маппинг
-- Layout использует символьные координаты: (colChar, lineChar).
-- HD-рендер переводит в пиксели:
--   px = (colChar - 1) * charPx * scale
--   py = (lineChar - 1) * linePx * scale
-- ---------------------------------------------------------------

local function layoutToPx(col, line)
    local px = (col - 1) * S.charPx * S.scale
    local py = (line - 1) * S.linePx * S.scale
    return px, py
end

M.layoutToPx = layoutToPx

function M.pxToLayout(px, py)
    local col = math.floor(px / (S.charPx * S.scale)) + 1
    local line = math.floor(py / (S.linePx * S.scale)) + 1
    return col, line
end

-- ---------------------------------------------------------------
-- Отрисовка страницы
-- ---------------------------------------------------------------

-- Выбор цвета для бокса с учётом темы.
local function pickFg(b, theme)
    local style = b.style or {}
    if style.fg then return toRgb(style.fg, {0, 0, 0}) end
    local t = b.type
    if t == "link" then return toRgb(theme.link_fg or theme.link or theme.accent, {80, 160, 255}) end
    if t == "button" then return toRgb(theme.button_fg, {0, 0, 0}) end
    if t == "input" then return toRgb(theme.input_fg, {255, 255, 255}) end
    if t == "hr" then return toRgb(theme.hr or theme.chrome_fg, {128, 128, 128}) end
    return toRgb(theme.fg, {240, 240, 240})
end

local function pickBg(b, theme)
    local style = b.style or {}
    if style.bg then return toRgb(style.bg, {0, 0, 0}) end
    local t = b.type
    if t == "button" then return toRgb(theme.button_bg, {80, 200, 40}) end
    if t == "input" then return toRgb(theme.input_bg, {64, 64, 64}) end
    return nil  -- прозрачный → не рисуем bg
end

--- Отрисовка layout-боксов в HDMonitor.
-- @param boxes array из layout.compute
-- @param scrollY скролл в "символьных" единицах
-- @param viewport {charsW, linesH}  -- опционально, иначе считается по экрану
function M.drawPage(boxes, scrollY, viewport)
    local d = dev(); if not d then return end
    local theme = S.theme
    scrollY = scrollY or 0
    viewport = viewport or { charsW = M.charsPerLine(), linesH = M.linesPerScreen() }

    local bgR, bgG, bgB = toRgb(theme.bg, {0, 0, 0})
    M.clear(bgR, bgG, bgB)

    if not boxes then M.flush(); return end

    local charPx = S.charPx * S.scale
    local linePx = S.linePx * S.scale
    local screenPxH = S.pxH

    -- Пасс 1: background blocks
    for _, b in ipairs(boxes) do
        if b.type == "bg" and b.style and b.style.bg then
            local px, py = layoutToPx(b.x or 1, (b.y or 1) - scrollY)
            local pw = (b.w or 1) * charPx
            local ph = (b.h or 1) * linePx
            if py + ph > 0 and py < screenPxH then
                local r, g, bl = toRgb(b.style.bg, {0, 0, 0})
                M.drawRect(px, py, pw, ph, r, g, bl)
            end
        end
    end

    -- Пасс 2: картинки (если byte-данные уже загружены в b._rgbBytes)
    for _, b in ipairs(boxes) do
        if b.type == "image" and b._rgbBytes and b._rgbW and b._rgbH then
            local px, py = layoutToPx(b.x or 1, (b.y or 1) - scrollY)
            if py + b._rgbH > 0 and py < screenPxH then
                M.drawImage(px, py, b._rgbW, b._rgbH, b._rgbBytes)
            end
        elseif b.type == "image" and b._pending then
            -- Плейсхолдер-рамка пока картинка грузится.
            local px, py = layoutToPx(b.x or 1, (b.y or 1) - scrollY)
            local pw = (b.w or 4) * charPx
            local ph = (b.h or 2) * linePx
            if py + ph > 0 and py < screenPxH then
                M.drawRect(px, py, pw, ph, 32, 32, 48)
                M.drawText(px + 2, py + 2, "[img]", 128, 160, 200, 1)
            end
        end
    end

    -- Пасс 3: текст + ссылки + кнопки
    for _, b in ipairs(boxes) do
        local t = b.type
        if t and t ~= "bg" and t ~= "image" then
            local style = b.style or {}
            if not style.hidden then
                local px, py = layoutToPx(b.x or 1, (b.y or 1) - scrollY)
                if py + linePx > 0 and py < screenPxH then
                    -- фон, если задан явно
                    local bg = pickBg(b, theme)
                    if bg then
                        local bw = (b.w or #(b.text or "")) * charPx
                        local bh = (b.h or 1) * linePx
                        M.drawRect(px, py, bw, bh, bg[1] or 0, bg[2] or 0, bg[3] or 0)
                    end
                    local fr, fg, fbl = pickFg(b, theme)
                    local txt
                    if t == "hr" then
                        local w = (b.w or 8) * charPx
                        -- Горизонтальная линия = тонкий rect в центре строки.
                        M.drawRect(px, py + math.floor(linePx / 2), w, math.max(1, S.scale), fr, fg, fbl)
                    else
                        txt = b.text or ""
                        if txt ~= "" then
                            -- Используем scale шрифта из стиля (например h1),
                            -- иначе общий S.scale.
                            local sc = style.textScale or S.scale
                            M.drawText(px, py, txt, fr, fg, fbl, sc)
                            -- underline для ссылок
                            if t == "link" or style.underline then
                                local ulw = #txt * S.charPx * sc
                                M.drawRect(px, py + S.linePx * sc - math.max(1, sc),
                                    ulw, math.max(1, sc), fr, fg, fbl)
                            end
                        end
                    end
                end
            end
        end
    end

    M.flush()
end

-- ---------------------------------------------------------------
-- Hit-test по пиксельным координатам
-- ---------------------------------------------------------------

function M.hitTest(boxes, pxX, pxY, scrollY, viewport)  -- luacheck: ignore viewport
    if not boxes then return nil end
    scrollY = scrollY or 0
    local col, line = M.pxToLayout(pxX, pxY)
    local docY = line + scrollY
    for _, b in ipairs(boxes) do
        local bx = b.x or 1
        local by = b.y or 1
        local bw = b.w or #(b.text or "")
        local bh = b.h or 1
        if col >= bx and col <= bx + bw - 1
           and docY >= by and docY <= by + bh - 1 then
            return b
        end
    end
    return nil
end

return M
