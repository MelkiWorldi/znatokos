-- Taskbar внизу экрана. Адаптивный: на узких экранах кнопка «Пуск» сжимается.
local theme = znatokos.use("ui/theme")
local wm    = znatokos.use("kernel/window")
local text  = znatokos.use("util/text")

local M = {}
local parent = term

function M.setParent(t) parent = t end

local function startLabel()
    local sw = parent.getSize()
    if sw < 30 then return " > " end
    return " > Пуск "
end

function M.draw()
    local th = theme.get()
    local w, h = parent.getSize()
    parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.taskbar_fg)
    parent.setCursorPos(1, h); parent.write(string.rep(" ", w))
    -- Кнопка «Пуск»
    local startL = startLabel()
    local startW = text.len(startL)
    parent.setCursorPos(1, h)
    parent.setBackgroundColor(th.accent); parent.setTextColor(colors.black)
    parent.write(startL)
    -- Вкладки окон
    parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.taskbar_fg)
    local x = startW + 2
    local focused = wm.getFocused()
    local clockW = 6
    for _, win in ipairs(wm.list()) do
        local maxLabelW = math.max(4, math.floor((w - x - clockW) / math.max(1, #wm.list())) - 2)
        local label = text.ellipsize(win.title, maxLabelW)
        local lw = text.len(label) + 2
        if x + lw >= w - clockW then break end
        if focused and focused.id == win.id then
            parent.setBackgroundColor(th.title_bg); parent.setTextColor(th.title_fg)
        else
            parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.taskbar_fg)
        end
        parent.setCursorPos(x, h); parent.write(" " .. label .. " ")
        win._tab_x = x; win._tab_w = lw
        x = x + lw + 1
    end
    -- Часы справа
    parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.accent)
    local clock = textutils.formatTime(os.time(), true)
    parent.setCursorPos(w - text.len(clock), h); parent.write(clock)
end

-- Возвращает: "start" / "window" / "clock" / nil
function M.handleClick(x, y)
    local w, h = parent.getSize()
    if y ~= h then return nil end
    local startW = text.len(startLabel())
    if x <= startW then return "start" end
    for _, win in ipairs(wm.list()) do
        if win._tab_x and x >= win._tab_x and x <= win._tab_x + win._tab_w - 1 then
            wm.focus(win.id); return "window"
        end
    end
    local clockL = textutils.formatTime(os.time(), true)
    if x >= w - text.len(clockL) then return "clock" end
    return nil
end

return M
