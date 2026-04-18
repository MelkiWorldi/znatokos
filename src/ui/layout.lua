-- Простой layout engine: row / column / grid / flex / percent.
-- Работает с rect'ами. Каждый child — таблица:
--   { w = 10 }  фикс (целое)
--   { w = "20%" } процент от parent
--   { flex = 1 } растягивается пропорционально остатку
--   { h = ... } то же для высоты
--
-- Функции возвращают массив прямоугольников {x, y, w, h} для детей.
local M = {}

local function resolveSize(spec, parent, usedForFlex)
    if type(spec) == "number" then return spec end
    if type(spec) == "string" then
        local p = spec:match("^(%d+)%%$")
        if p then return math.floor(parent * tonumber(p) / 100) end
        local n = tonumber(spec); if n then return n end
    end
    return nil
end

-- row: дети располагаются слева направо, разделяются gap.
-- opts = { x, y, w, h, gap = 0, children = {...} }
function M.row(opts)
    local x, y, w, h = opts.x or 1, opts.y or 1, opts.w or 1, opts.h or 1
    local gap = opts.gap or 0
    local children = opts.children or {}
    local n = #children
    local gapsTotal = gap * math.max(0, n - 1)

    local fixed, flexTotal = 0, 0
    local sizes = {}
    for i, ch in ipairs(children) do
        local sz = resolveSize(ch.w, w)
        if sz then sizes[i] = sz; fixed = fixed + sz
        elseif ch.flex then flexTotal = flexTotal + ch.flex
        else sizes[i] = 0 end
    end

    local remaining = math.max(0, w - fixed - gapsTotal)
    for i, ch in ipairs(children) do
        if not sizes[i] and ch.flex then
            sizes[i] = math.floor(remaining * ch.flex / flexTotal)
        end
    end

    local out = {}
    local cx = x
    for i, ch in ipairs(children) do
        out[i] = { x = cx, y = y, w = sizes[i] or 0, h = h, child = ch }
        cx = cx + (sizes[i] or 0) + gap
    end
    return out
end

-- column: дети сверху вниз
function M.column(opts)
    local x, y, w, h = opts.x or 1, opts.y or 1, opts.w or 1, opts.h or 1
    local gap = opts.gap or 0
    local children = opts.children or {}
    local n = #children
    local gapsTotal = gap * math.max(0, n - 1)

    local fixed, flexTotal = 0, 0
    local sizes = {}
    for i, ch in ipairs(children) do
        local sz = resolveSize(ch.h, h)
        if sz then sizes[i] = sz; fixed = fixed + sz
        elseif ch.flex then flexTotal = flexTotal + ch.flex
        else sizes[i] = 0 end
    end

    local remaining = math.max(0, h - fixed - gapsTotal)
    for i, ch in ipairs(children) do
        if not sizes[i] and ch.flex then
            sizes[i] = math.floor(remaining * ch.flex / flexTotal)
        end
    end

    local out = {}
    local cy = y
    for i, ch in ipairs(children) do
        out[i] = { x = x, y = cy, w = w, h = sizes[i] or 0, child = ch }
        cy = cy + (sizes[i] or 0) + gap
    end
    return out
end

-- grid: cols × rows равных ячеек; дети идут по строкам
function M.grid(opts)
    local x, y, w, h = opts.x or 1, opts.y or 1, opts.w or 1, opts.h or 1
    local cols = opts.cols or 1
    local rows = opts.rows or 1
    local gapX = opts.gapX or opts.gap or 0
    local gapY = opts.gapY or opts.gap or 0
    local cellW = math.floor((w - gapX * (cols - 1)) / cols)
    local cellH = math.floor((h - gapY * (rows - 1)) / rows)
    local children = opts.children or {}
    local out = {}
    for i, ch in ipairs(children) do
        if i > cols * rows then break end
        local c = (i - 1) % cols
        local r = math.floor((i - 1) / cols)
        out[i] = {
            x = x + c * (cellW + gapX),
            y = y + r * (cellH + gapY),
            w = cellW, h = cellH, child = ch,
        }
    end
    return out
end

-- center: вложить контент фикс. размера в родителя и центрировать
function M.center(parentX, parentY, parentW, parentH, childW, childH)
    local cw = math.min(childW, parentW)
    local ch = math.min(childH, parentH)
    local cx = parentX + math.max(0, math.floor((parentW - cw) / 2))
    local cy = parentY + math.max(0, math.floor((parentH - ch) / 2))
    return cx, cy, cw, ch
end

return M
