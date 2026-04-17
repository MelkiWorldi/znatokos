-- Рабочий стол. Иконки, меню «Пуск», запуск приложений в окнах.
local theme   = znatokos.use("ui/theme")
local wm      = znatokos.use("kernel/window")
local sched   = znatokos.use("kernel/scheduler")
local widgets = znatokos.use("ui/widgets")
local dialog  = znatokos.use("ui/dialog")
local taskbar = znatokos.use("ui/taskbar")
local paths   = znatokos.use("fs/paths")
local log     = znatokos.use("kernel/log")

local M = {}

local ICONS = {
    { label = "Терминал",  col = colors.lime,     app = "terminal"    },
    { label = "Файлы",     col = colors.yellow,   app = "filemanager" },
    { label = "Настройки", col = colors.lightBlue,app = "settings"    },
    { label = "Часы",      col = colors.white,    app = "clock"       },
    { label = "Калькулятор", col = colors.orange, app = "calc"        },
    { label = "Змейка",    col = colors.green,    app = "snake"       },
    { label = "Paint",     col = colors.pink,     app = "paint"       },
    { label = "Чат",       col = colors.magenta,  app = "chat"        },
}

local function runApp(appName, user, title)
    local appPath = paths.APPS .. "/" .. appName .. ".lua"
    if not fs.exists(appPath) then
        -- возможно, это команда
        appPath = paths.COMMANDS .. "/" .. appName .. ".lua"
    end
    if not fs.exists(appPath) then
        dialog.message("Ошибка", "Приложение не найдено:\n" .. appName)
        return
    end
    local win = wm.create({ title = title or appName, owner = user.user,
                            w = 45, h = 15, x = 3, y = 2 })
    sched.spawn({
        name = appName,
        owner = user.user,
        window = win,
        fn = function()
            local prev = term.redirect(win.win)
            wm.focus(win.id)
            local ok, err = pcall(function()
                local fn, e = loadfile(appPath, nil, _G)
                if not fn then error(e) end
                fn(user)
            end)
            term.redirect(prev)
            if not ok then
                log.error("app " .. appName .. ": " .. tostring(err))
                dialog.message("Сбой приложения", tostring(err))
            end
            wm.destroy(win.id)
        end,
    })
end

local function drawIcons(user)
    local th = theme.get()
    local sw, sh = term.getSize()
    term.setBackgroundColor(th.desktop); term.clear()
    term.setTextColor(colors.white)
    term.setCursorPos(2, 1); term.write("ЗнатокOS — " .. user.user)
    local x, y = 2, 3
    for i, ic in ipairs(ICONS) do
        term.setBackgroundColor(ic.col); term.setTextColor(colors.black)
        term.setCursorPos(x, y);     term.write("  ")
        term.setCursorPos(x, y + 1); term.write("  ")
        term.setBackgroundColor(th.desktop); term.setTextColor(colors.white)
        local label = ic.label
        if #label > 12 then label = label:sub(1, 12) end
        term.setCursorPos(x - math.floor((#label - 2) / 2), y + 2)
        term.write(label)
        ic._x = x; ic._y = y; ic._w = 2; ic._h = 2
        x = x + 12
        if x + 2 > sw then x = 2; y = y + 4 end
    end
    taskbar.draw()
end

local function iconAt(mx, my)
    for _, ic in ipairs(ICONS) do
        if ic._x and mx >= ic._x and mx <= ic._x + ic._w - 1
           and my >= ic._y and my <= ic._y + ic._h - 1 then
            return ic
        end
    end
    return nil
end

local function startMenu(user)
    local sw, sh = term.getSize()
    local items = {
        { label = "Терминал",   action = function() runApp("terminal", user, "Терминал") end },
        { label = "Файлы",      action = function() runApp("filemanager", user, "Файлы") end },
        { label = "Настройки",  action = function() runApp("settings", user, "Настройки") end },
        { label = "Калькулятор", action = function() runApp("calc", user, "Калькулятор") end },
        { label = "Часы",       action = function() runApp("clock", user, "Часы") end },
        { label = "Змейка",     action = function() runApp("snake", user, "Змейка") end },
        { label = "Paint",      action = function() runApp("paint", user, "Paint") end },
        { label = "Чат (сеть)", action = function() runApp("chat", user, "Чат") end },
        { label = "─────────", action = function() end },
        { label = "Выход",      action = function() _G._znatokos_exit = true end },
        { label = "Reboot",     action = function() os.reboot() end },
        { label = "Shutdown",   action = function() os.shutdown() end },
    }
    local h = #items
    local y = sh - h - 1
    if y < 1 then y = 1 end
    local m = widgets.menu({ x = 1, y = y, items = items })
    m:draw(term)
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if mx >= 1 and mx <= m.w and my >= y and my <= y + h - 1 then
                m:event(ev)
                return
            else
                return
            end
        elseif ev[1] == "key" and (ev[2] == keys.escape or ev[2] == keys.enter) then
            m:event(ev); return
        else
            m:event(ev)
        end
    end
end

function M.run(user)
    _G._znatokos_exit = false
    drawIcons(user)
    -- фоновая задача для часов
    sched.spawn({
        name = "taskbar-clock",
        owner = user.user,
        fn = function()
            while true do
                sleep(10)
                if not _G._znatokos_exit then taskbar.draw() end
            end
        end,
    })
    -- основной цикл событий рабочего стола
    sched.spawn({
        name = "desktop",
        owner = user.user,
        fn = function()
            local lastClick = { x = 0, y = 0, t = 0 }
            while not _G._znatokos_exit do
                taskbar.draw()
                local ev = { os.pullEvent() }
                if ev[1] == "mouse_click" and ev[2] == 1 then
                    local mx, my = ev[3], ev[4]
                    local tb = taskbar.handleClick(mx, my)
                    if tb == "start" then
                        startMenu(user)
                        drawIcons(user)
                    elseif tb == "window" then
                        -- focus уже сделан
                    elseif tb == "clock" then
                        dialog.message("Часы", textutils.formatTime(os.time(), true)
                            .. "\nДень: " .. os.day())
                        drawIcons(user)
                    else
                        local ic = iconAt(mx, my)
                        if ic then
                            local now = os.clock()
                            if now - lastClick.t < 0.5
                               and math.abs(mx - lastClick.x) <= 1
                               and math.abs(my - lastClick.y) <= 1 then
                                runApp(ic.app, user, ic.label)
                                drawIcons(user)
                                lastClick.t = 0
                            else
                                lastClick = { x = mx, y = my, t = now }
                            end
                        end
                    end
                elseif ev[1] == "key" and ev[2] == keys.f10 then
                    startMenu(user); drawIcons(user)
                elseif ev[1] == "key" and ev[2] == keys.tab then
                    -- Ctrl+Tab переключение окон
                    -- CC посылает отдельные key-события; проверяем глобальный leftCtrl
                    -- Упрощённо: Tab без модификаторов тоже переключает
                    wm.nextWindow()
                end
            end
        end,
    })

    sched.run()
end

return M
