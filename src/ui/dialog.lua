-- Модальные диалоги. Блокирующие.
local theme   = znatokos.use("ui/theme")
local widgets = znatokos.use("ui/widgets")

local M = {}

local function drawFrame(x, y, w, h, title)
    local th = theme.get()
    widgets.fill(term, x, y, w, h, th.bg)
    term.setBackgroundColor(th.title_bg); term.setTextColor(th.title_fg)
    term.setCursorPos(x, y)
    local t = " " .. (title or "") .. string.rep(" ", math.max(0, w - #(title or "") - 2))
    term.write(t:sub(1, w))
end

local function center(w, h)
    local sw, sh = term.getSize()
    return math.floor((sw - w) / 2) + 1, math.floor((sh - h) / 2) + 1
end

-- message: одна кнопка OK
function M.message(title, text)
    local th = theme.get()
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    local w = 30
    for _, l in ipairs(lines) do if #l + 4 > w then w = #l + 4 end end
    local h = #lines + 4
    local x, y = center(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    for i, l in ipairs(lines) do
        term.setCursorPos(x + 2, y + i)
        term.write(l)
    end
    local btn = widgets.button({ x = x + w - 7, y = y + h - 2, w = 5, label = "OK" })
    btn:draw(term)
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "key" and ev[2] == keys.enter then return
        elseif ev[1] == "mouse_click" and btn:hit(ev[3], ev[4]) then return
        end
    end
end

-- confirm: Yes/No
function M.confirm(title, text)
    local th = theme.get()
    local w = math.max(30, #text + 4)
    local h = 5
    local x, y = center(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    term.setCursorPos(x + 2, y + 1); term.write(text)
    local result
    local yes = widgets.button({ x = x + 2, y = y + 3, w = 8, label = "Да",
        onClick = function() result = true end })
    local no  = widgets.button({ x = x + w - 10, y = y + 3, w = 8, label = "Нет",
        onClick = function() result = false end })
    yes:draw(term); no:draw(term)
    while result == nil do
        local ev = { os.pullEvent() }
        yes:event(ev); no:event(ev)
        if ev[1] == "key" then
            if ev[2] == keys.y then result = true
            elseif ev[2] == keys.n or ev[2] == keys.escape then result = false end
        end
    end
    return result
end

-- input: текстовый ввод
function M.input(title, prompt, default, mask)
    local th = theme.get()
    local w = 32; local h = 6
    local x, y = center(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    term.setCursorPos(x + 2, y + 1); term.write(prompt or "")
    local inp = widgets.input({ x = x + 2, y = y + 2, w = w - 4, value = default or "", mask = mask })
    local ok  = widgets.button({ x = x + 2,     y = y + 4, w = 8, label = "OK" })
    local ca  = widgets.button({ x = x + w - 10, y = y + 4, w = 8, label = "Отмена" })
    inp:draw(term); ok:draw(term); ca:draw(term)
    while true do
        local ev = { os.pullEvent() }
        local r = inp:event(ev)
        if type(r) == "table" and r.done then return r.value end
        if ev[1] == "mouse_click" then
            if ok:hit(ev[3], ev[4]) then return inp.value
            elseif ca:hit(ev[3], ev[4]) then return nil end
        end
        if ev[1] == "key" and ev[2] == keys.escape then return nil end
    end
end

return M
