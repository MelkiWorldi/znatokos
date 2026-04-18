-- render.lua — базовый рендерер браузера ZnatokOS.
-- Рисует боксы из layout.compute на терминал.
-- В этой версии win-аргумент не используется напрямую: app-scheduler
-- уже перенаправил term на окно приложения, поэтому работаем через term.

local M = {}

local DEFAULT_THEME = {
    bg = colors.white,
    fg = colors.black,
    link = colors.blue,
    button_bg = colors.lightGray,
    button_fg = colors.black,
    input_bg = colors.lightGray,
    input_fg = colors.black,
    hr = colors.gray,
    status_bg = colors.gray,
    status_fg = colors.white,
}

local function mergeTheme(theme)
    local t = {}
    for k, v in pairs(DEFAULT_THEME) do t[k] = v end
    if theme then
        for k, v in pairs(theme) do t[k] = v end
    end
    return t
end

-- Очистить прямоугольный регион цветом bg.
local function clearRegion(x1, y1, x2, y2, bg)
    term.setBackgroundColor(bg)
    local blank = string.rep(" ", math.max(0, x2 - x1 + 1))
    for y = y1, y2 do
        term.setCursorPos(x1, y)
        term.write(blank)
    end
end

--- Рисование набора боксов в viewport.
-- @param win     окно (игнорируется, оставлено для совместимости с API)
-- @param boxes   массив { {x,y,w,h,type,text,style,...}, ... } из layout.compute
-- @param viewport { scrollY=number, width=number, height=number, x=number?, y=number? }
-- @param theme   опциональная тема
function M.draw(win, boxes, viewport, theme)
    theme = mergeTheme(theme)
    local vx = viewport.x or 1
    local vy = viewport.y or 1
    local vw = viewport.width or term.getSize()
    local vh = viewport.height or select(2, term.getSize())
    local scrollY = viewport.scrollY or 0

    -- Очистить область viewport'а.
    clearRegion(vx, vy, vx + vw - 1, vy + vh - 1, theme.bg)

    if not boxes then return end

    for _, b in ipairs(boxes) do
        local bx = b.x or 1
        local by = b.y or 1
        local screenY = vy + (by - 1) - scrollY
        if screenY >= vy and screenY <= vy + vh - 1 then
            local style = b.style or {}
            local bg = style.bg or theme.bg
            local fg = style.fg or theme.fg
            local bt = b.type or "text"

            if bt == "link" then
                fg = style.fg or theme.link
            elseif bt == "button" then
                bg = style.bg or theme.button_bg
                fg = style.fg or theme.button_fg
            elseif bt == "input" then
                bg = style.bg or theme.input_bg
                fg = style.fg or theme.input_fg
            elseif bt == "hr" then
                fg = style.fg or theme.hr
            end

            local drawX = vx + (bx - 1)
            if drawX < vx then drawX = vx end
            if drawX <= vx + vw - 1 then
                term.setCursorPos(drawX, screenY)
                term.setBackgroundColor(bg)
                term.setTextColor(fg)

                local txt
                if bt == "button" then
                    txt = "[ " .. (b.text or "") .. " ]"
                elseif bt == "input" then
                    local w = b.w or 10
                    local val = b.value or b.text or ""
                    if #val > w - 2 then val = val:sub(-(w - 2)) end
                    local pad = string.rep("_", math.max(0, w - 2 - #val))
                    txt = "[" .. val .. pad .. "]"
                elseif bt == "hr" then
                    local w = b.w or (vw - (bx - 1))
                    txt = string.rep("-", math.max(1, w))
                else
                    txt = b.text or ""
                end

                -- Обрезать по правому краю viewport'а.
                local maxLen = (vx + vw - 1) - drawX + 1
                if #txt > maxLen then txt = txt:sub(1, maxLen) end
                term.write(txt)
            end
        end
    end
end

--- Нарисовать статус-строку.
function M.drawStatusBar(win, text, y, theme)
    theme = mergeTheme(theme)
    local w, h = term.getSize()
    local ly = y or h
    term.setCursorPos(1, ly)
    term.setBackgroundColor(theme.status_bg)
    term.setTextColor(theme.status_fg)
    local s = tostring(text or "")
    if #s > w then s = s:sub(1, w) end
    s = s .. string.rep(" ", w - #s)
    term.write(s)
end

--- Найти бокс под клик.
-- @param boxes   набор боксов
-- @param clickX  экранный X
-- @param clickY  экранный Y
-- @param scrollY скролл viewport'а
-- @param viewport опционально { x=, y=, width=, height= } — если клик внутри
-- @return box или nil
function M.hitTest(boxes, clickX, clickY, scrollY, viewport)
    if not boxes then return nil end
    scrollY = scrollY or 0
    local vx = (viewport and viewport.x) or 1
    local vy = (viewport and viewport.y) or 1

    -- Переводим экранные координаты в координаты документа.
    local docX = clickX - (vx - 1)
    local docY = clickY - (vy - 1) + scrollY

    for _, b in ipairs(boxes) do
        local bx = b.x or 1
        local by = b.y or 1
        local bw = b.w or #(b.text or "")
        local bh = b.h or 1
        if docX >= bx and docX <= bx + bw - 1
           and docY >= by and docY <= by + bh - 1 then
            return b
        end
    end
    return nil
end

return M
