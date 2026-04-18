-- Модальные диалоги. Адаптивные размеры, word-wrap для длинных текстов,
-- Tab-навигация между кнопками.
local theme   = znatokos.use("ui/theme")
local widgets = znatokos.use("ui/widgets")
local layout  = znatokos.use("ui/layout")
local focus   = znatokos.use("ui/focus")
local text    = znatokos.use("util/text")

local M = {}

local function drawFrame(x, y, w, h, title)
    local th = theme.get()
    widgets.fill(term, x, y, w, h, th.bg)
    term.setBackgroundColor(th.title_bg); term.setTextColor(th.title_fg)
    term.setCursorPos(x, y)
    term.write(text.pad(" " .. (title or ""), w))
end

local function centerRect(w, h)
    local sw, sh = term.getSize()
    return math.floor((sw - w) / 2) + 1, math.floor((sh - h) / 2) + 1
end

local function runModal(widgetList, initialFocus)
    local current = initialFocus
    if current and current.onFocus then current:onFocus() end
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "key" then
            if ev[2] == keys.escape then return nil end
            local handled, nxt = focus.handleKey(widgetList, current, ev[2], false)
            if handled then
                -- focus уже применил onFocus/onBlur
                current = nxt
            end
        end
        if current and current.event then
            local r = current:event(ev)
            -- если виджет вернул {requestFocus = target}, переключаем фокус
            if type(r) == "table" and r.requestFocus then
                if current and current.onBlur then current:onBlur() end
                current = r.requestFocus
                if current.onFocus then current:onFocus() end
            end
        end
        -- дать шанс остальным виджетам обработать клик
        for _, w in ipairs(widgetList) do
            if w ~= current and w.event then
                local r = w:event(ev)
                if type(r) == "table" and r.requestFocus then
                    if current and current.onBlur then current:onBlur() end
                    current = r.requestFocus
                    if current.onFocus then current:onFocus() end
                end
            end
        end
        if _G._dialog_result ~= nil then
            local r = _G._dialog_result; _G._dialog_result = nil
            return r
        end
    end
end

-- message: одна кнопка OK
function M.message(title, body)
    local th = theme.get()
    local sw, sh = term.getSize()
    local maxW = math.max(30, math.min(sw - 4, 50))
    local lines = text.wrap(body or "", maxW - 4)
    local bodyW = 0
    for _, l in ipairs(lines) do bodyW = math.max(bodyW, text.len(l)) end
    local w = math.max(math.min(maxW, bodyW + 4), 20)
    local h = math.min(sh - 2, #lines + 4)
    local x, y = centerRect(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    for i, l in ipairs(lines) do
        if i + y > y + h - 3 then break end
        term.setCursorPos(x + 2, y + i)
        term.write(l)
    end

    local ok
    local btn = widgets.button({
        x = x + math.floor((w - 6) / 2), y = y + h - 2,
        w = 6, label = "OK",
        onClick = function() _G._dialog_result = true end,
    })
    btn:draw()
    runModal({ btn }, btn)
end

-- confirm: Yes/No
function M.confirm(title, body)
    local th = theme.get()
    local sw, sh = term.getSize()
    local maxW = math.max(30, math.min(sw - 4, 50))
    local lines = text.wrap(body or "", maxW - 4)
    local bodyW = 20
    for _, l in ipairs(lines) do bodyW = math.max(bodyW, text.len(l)) end
    local w = math.max(math.min(maxW, bodyW + 4), 20)
    local h = math.min(sh - 2, #lines + 4)
    local x, y = centerRect(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    for i, l in ipairs(lines) do
        term.setCursorPos(x + 2, y + i); term.write(l)
    end
    local yes = widgets.button({
        x = x + 2, y = y + h - 2, w = 8, label = "Да",
        onClick = function() _G._dialog_result = true end,
    })
    local no = widgets.button({
        x = x + w - 10, y = y + h - 2, w = 8, label = "Нет",
        onClick = function() _G._dialog_result = false end,
    })
    yes:draw(); no:draw()
    return runModal({ yes, no }, yes)
end

-- input: текстовое поле с OK/Cancel
function M.input(title, prompt, default, mask)
    local th = theme.get()
    local sw, sh = term.getSize()
    local w = math.min(sw - 4, 40); local h = 7
    local x, y = centerRect(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    term.setCursorPos(x + 2, y + 1); term.write(text.ellipsize(prompt or "", w - 4))
    local inp = widgets.input({
        x = x + 2, y = y + 3, w = w - 4, value = default or "", mask = mask,
        onSubmit = function(v) _G._dialog_result = v end,
    })
    local ok = widgets.button({
        x = x + 2, y = y + h - 2, w = 6, label = "OK",
        onClick = function() _G._dialog_result = inp.value end,
    })
    local ca = widgets.button({
        x = x + w - 8, y = y + h - 2, w = 8, label = "Отмена",
        onClick = function() _G._dialog_result = false end,
    })
    inp:draw(); ok:draw(); ca:draw()
    local r = runModal({ inp, ok, ca }, inp)
    if r == false then return nil end
    return r
end

return M
