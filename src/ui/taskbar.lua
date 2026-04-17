-- Taskbar внизу экрана: кнопка «Пуск», список окон, часы.
local theme = znatokos.use("ui/theme")
local wm    = znatokos.use("kernel/window")

local M = {}
local parent = term

function M.setParent(t) parent = t end

function M.draw()
    local th = theme.get()
    local w, h = parent.getSize()
    parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.taskbar_fg)
    parent.setCursorPos(1, h); parent.write(string.rep(" ", w))
    -- Кнопка "Пуск"
    parent.setCursorPos(1, h)
    parent.setBackgroundColor(th.accent); parent.setTextColor(colors.black)
    parent.write(" ▼ Пуск ")
    -- Окна
    parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.taskbar_fg)
    local x = 10
    local focused = wm.getFocused()
    for _, win in ipairs(wm.list()) do
        local label = win.title
        if #label > 10 then label = label:sub(1, 10) end
        if focused and focused.id == win.id then
            parent.setBackgroundColor(th.title_bg); parent.setTextColor(th.title_fg)
        else
            parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.taskbar_fg)
        end
        parent.setCursorPos(x, h); parent.write(" " .. label .. " ")
        win._tab_x = x; win._tab_w = #label + 2
        x = x + #label + 3
    end
    -- Часы
    parent.setBackgroundColor(th.taskbar_bg); parent.setTextColor(th.accent)
    local clock = textutils.formatTime(os.time(), true)
    parent.setCursorPos(w - #clock, h); parent.write(clock)
end

-- Обработка кликов по taskbar. Возвращает "start" если кликнули «Пуск»,
-- или pid окна при клике на его вкладку, иначе nil.
function M.handleClick(x, y)
    local _, h = parent.getSize()
    if y ~= h then return nil end
    if x <= 9 then return "start" end
    for _, win in ipairs(wm.list()) do
        if win._tab_x and x >= win._tab_x and x <= win._tab_x + win._tab_w - 1 then
            wm.focus(win.id)
            return "window"
        end
    end
    local sw = parent.getSize()
    if x >= sw - 5 then return "clock" end
    return nil
end

return M
