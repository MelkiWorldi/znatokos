-- Focus-ring: навигация по фокусируемым элементам клавишами.
-- Элемент-фокусируемый = таблица с полями {x, y, w, h, onFocus, onBlur, onActivate}.
-- Контейнер хранит список, focus.lua предоставляет next/prev/geometric move.
local M = {}

local function center(it)
    return it.x + it.w / 2, it.y + it.h / 2
end

-- Следующий по табу (простой порядок массива)
function M.next(items, current)
    if #items == 0 then return nil end
    if not current then return items[1] end
    for i, it in ipairs(items) do
        if it == current then
            return items[(i % #items) + 1]
        end
    end
    return items[1]
end

function M.prev(items, current)
    if #items == 0 then return nil end
    if not current then return items[#items] end
    for i, it in ipairs(items) do
        if it == current then
            local p = i - 1; if p < 1 then p = #items end
            return items[p]
        end
    end
    return items[1]
end

-- Геометрический обход по направлению ("up"/"down"/"left"/"right").
-- Находит ближайший элемент в указанном направлении от current.
function M.move(items, current, dir)
    if #items == 0 then return nil end
    if not current then return items[1] end
    local cx, cy = center(current)
    local best, bestDist = nil, math.huge
    for _, it in ipairs(items) do
        if it ~= current then
            local ix, iy = center(it)
            local dx, dy = ix - cx, iy - cy
            local ok = false
            if dir == "right" and dx > 0.5 then ok = true
            elseif dir == "left" and dx < -0.5 then ok = true
            elseif dir == "down" and dy > 0.5 then ok = true
            elseif dir == "up" and dy < -0.5 then ok = true
            end
            if ok then
                -- Штраф за перпендикулярную ось
                local parallel, perp
                if dir == "left" or dir == "right" then
                    parallel = math.abs(dx); perp = math.abs(dy) * 2
                else
                    parallel = math.abs(dy); perp = math.abs(dx) * 2
                end
                local dist = parallel + perp
                if dist < bestDist then best = it; bestDist = dist end
            end
        end
    end
    return best
end

-- Обработчик клавиш. Возвращает true, если событие обработано.
-- current может меняться (возвращается вторым значением).
-- Ключевые клавиши: Tab, Shift+Tab, arrows, Enter/Space.
function M.handleKey(items, current, key, shift)
    if #items == 0 then return false, current end
    if key == keys.tab then
        local nxt = shift and M.prev(items, current) or M.next(items, current)
        if current and current.onBlur then current:onBlur() end
        if nxt and nxt.onFocus then nxt:onFocus() end
        return true, nxt
    elseif key == keys.up or key == keys.down or key == keys.left or key == keys.right then
        local dirs = { [keys.up]="up", [keys.down]="down", [keys.left]="left", [keys.right]="right" }
        local nxt = M.move(items, current, dirs[key])
        if nxt then
            if current and current.onBlur then current:onBlur() end
            if nxt.onFocus then nxt:onFocus() end
            return true, nxt
        end
    elseif key == keys.space then
        if current and current.onActivate then
            current:onActivate(); return true, current
        end
    elseif key == keys.enter then
        -- Для input'ов Enter обрабатывает сам виджет (вызывает onSubmit)
        -- чтобы не дублировать; button активируется
        if current and current.onActivate and current.onSubmit == nil then
            current:onActivate(); return true, current
        end
    end
    return false, current
end

return M
