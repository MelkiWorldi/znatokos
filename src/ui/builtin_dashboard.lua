-- Компактная панель статуса на встроенном экране компа.
-- Запускается фоновой задачей, обновляется каждые 2 секунды.
-- Показывает: версию, пользователя, время, размер плоскости,
-- число задач, напоминание что OS на мониторе.
local theme   = znatokos.use("ui/theme")
local display = znatokos.use("kernel/display")
local sched   = znatokos.use("kernel/scheduler")
local vfs     = znatokos.use("fs/vfs")
local text    = znatokos.use("util/text")

local M = {}

local function draw()
    local builtin = display.getBuiltinTerm()
    if not builtin then return end
    local prev = term.redirect(builtin)
    local th = theme.get()
    local w, h = builtin.getSize()

    builtin.setBackgroundColor(colors.black)
    builtin.clear()

    -- Шапка
    builtin.setTextColor(colors.yellow)
    local title = "ЗнатокOS v" .. (_G.znatokos and _G.znatokos.VERSION or "?")
    builtin.setCursorPos(math.max(1, math.floor((w - text.len(title)) / 2) + 1), 1)
    builtin.write(title)

    -- Разделитель
    builtin.setTextColor(colors.gray)
    builtin.setCursorPos(1, 2); builtin.write(string.rep("-", w))

    -- Статус
    builtin.setTextColor(colors.white)
    local u = vfs.getUser() or { user = "—" }
    local lines = {
        ("User:    %s"):format(u.user or "—"),
        ("Время:   %s  день %d"):format(textutils.formatTime(os.time(), true), os.day()),
    }
    local pw, ph = display.current().getSize()
    lines[#lines + 1] = ("Экран:   %dx%d  (%s)"):format(pw, ph, display.kind())
    lines[#lines + 1] = ("Задач:   %d"):format(sched.count())

    for i, l in ipairs(lines) do
        builtin.setCursorPos(2, 3 + i)
        builtin.write(text.ellipsize(l, w - 2))
    end

    -- Список задач
    local tasks = sched.list()
    if #tasks > 0 and 3 + #lines + 2 < h - 3 then
        builtin.setTextColor(colors.lightGray)
        builtin.setCursorPos(2, 3 + #lines + 2)
        builtin.write("Активные задачи:")
        builtin.setTextColor(colors.white)
        local maxTasks = h - (3 + #lines + 3) - 3
        for i = 1, math.min(maxTasks, #tasks) do
            local t = tasks[i]
            builtin.setCursorPos(4, 3 + #lines + 2 + i)
            builtin.write(text.ellipsize(
                ("%d %s"):format(t.pid, t.name), w - 4))
        end
    end

    -- Подсказка внизу
    builtin.setTextColor(colors.gray)
    local hint = "OS активна на внешнем экране"
    builtin.setCursorPos(math.max(1, math.floor((w - text.len(hint)) / 2) + 1), h - 1)
    builtin.write(hint)
    local hint2 = "Ctrl+T для завершения"
    builtin.setCursorPos(math.max(1, math.floor((w - text.len(hint2)) / 2) + 1), h)
    builtin.write(hint2)

    term.redirect(prev)
end

-- Если OS на builtin — не стартуем, dashboard не нужен
function M.start()
    if not display.hasMonitor() then return end
    sched.spawn({
        name = "builtin-dashboard",
        owner = "system",
        fn = function()
            draw()
            while true do
                sleep(2)
                pcall(draw)
            end
        end,
    })
end

function M.redraw() pcall(draw) end

return M
