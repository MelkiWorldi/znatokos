-- Рабочий стол. Адаптивная сетка иконок, контекстные меню,
-- поддержка term_resize, интеграция с window chrome (close-button, drag).
local theme   = znatokos.use("ui/theme")
local wm      = znatokos.use("kernel/window")
local sched   = znatokos.use("kernel/scheduler")
local widgets = znatokos.use("ui/widgets")
local dialog  = znatokos.use("ui/dialog")
local taskbar = znatokos.use("ui/taskbar")
local paths   = znatokos.use("fs/paths")
local log     = znatokos.use("kernel/log")
local focus   = znatokos.use("ui/focus")
local pointer = znatokos.use("ui/pointer")
local layout  = znatokos.use("ui/layout")
local text    = znatokos.use("util/text")

local M = {}

local ICONS = {}

local function rebuildIcons(user)
    ICONS = {}
    -- Core apps в OS (legacy: /znatokos/src/apps/<name>.lua).
    -- Остальные (paint/snake/calc/clock/chat и другие) появляются
    -- динамически ниже через kernel/app.listInstalled().
    local systemApps = {
        { label = "Терминал",  col = colors.lime,      app = "terminal"    },
        { label = "Файлы",     col = colors.yellow,    app = "filemanager" },
        { label = "Настройки", col = colors.lightBlue, app = "settings"    },
        { label = "Магазин",   col = colors.cyan,      app = "store"       },
    }
    for _, ic in ipairs(systemApps) do ICONS[#ICONS+1] = ic end

    local ok_app, app = pcall(znatokos.use, "kernel/app")
    if ok_app and app.listInstalled then
        local ok_list, installed = pcall(app.listInstalled)
        if ok_list and installed then
            for _, info in ipairs(installed) do
                local m = info.manifest
                ICONS[#ICONS+1] = {
                    label = m.name,
                    col = (m.icon and m.icon.color) or colors.gray,
                    app = info.id,
                    glyph = m.icon and m.icon.glyph,
                }
            end
        end
    end
end

local focusedIconIdx = 1  -- для focus-ring

--------------------------------------------------------------
-- Запуск приложения в окне
--------------------------------------------------------------
local function runApp(appName, user, title)
    local ok_app, app = pcall(znatokos.use, "kernel/app")
    if not ok_app then
        dialog.message("Ошибка", "Модуль kernel/app не доступен")
        return
    end
    -- Пробуем как app-id (новый API с манифестом).
    -- Пытаемся короткое имя и привычный prefix com.znatok.<name>.
    local candidates = { appName, "com.znatok." .. appName }
    if app.isInstalled then
        for _, cid in ipairs(candidates) do
            if app.isInstalled(cid) then
                app.run(cid, user)
                return
            end
        end
    end
    -- Legacy: apps/, затем shell/commands/
    local appPath = paths.APPS .. "/" .. appName .. ".lua"
    if not fs.exists(appPath) then
        appPath = paths.COMMANDS .. "/" .. appName .. ".lua"
    end
    if not fs.exists(appPath) then
        dialog.message("Ошибка", "Приложение не найдено:\n" .. appName)
        return
    end
    app.runLegacy(appPath, { user = user, title = title or appName })
end

--------------------------------------------------------------
-- Адаптивная сетка иконок
--------------------------------------------------------------
local ICON_W, ICON_H = 2, 2      -- цветной блок
local CELL_W, CELL_H = 14, 4     -- шаг (с подписью)
local TOP_PAD = 2                -- место под заголовок

local function computeIconLayout()
    local sw, sh = term.getSize()
    local availW = sw - 2
    local cols = math.max(1, math.floor(availW / CELL_W))
    -- сбрасываем прошлые координаты, чтобы iconAt не матчил старьё
    for _, ic in ipairs(ICONS) do
        ic._x, ic._y, ic._w, ic._h = nil, nil, nil, nil
    end
    for i, ic in ipairs(ICONS) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        ic._x = 2 + col * CELL_W
        ic._y = TOP_PAD + 1 + row * CELL_H
        ic._w = ICON_W; ic._h = ICON_H
    end
end

local function drawIcons(user)
    computeIconLayout()
    local th = theme.get()
    term.setBackgroundColor(th.desktop); term.clear()
    term.setTextColor(colors.white)
    local title = "ЗнатокOS — " .. user.user
    term.setCursorPos(2, 1); term.write(title)
    for i, ic in ipairs(ICONS) do
        local isFocus = (i == focusedIconIdx)
        -- цветной блок
        term.setBackgroundColor(ic.col); term.setTextColor(colors.black)
        term.setCursorPos(ic._x, ic._y);     term.write("  ")
        term.setCursorPos(ic._x, ic._y + 1); term.write("  ")
        -- рамка фокуса
        if isFocus then
            term.setBackgroundColor(th.desktop); term.setTextColor(th.accent)
            term.setCursorPos(ic._x - 1, ic._y - 1); term.write("+--+")
            term.setCursorPos(ic._x - 1, ic._y);     term.write("|")
            term.setCursorPos(ic._x + 2, ic._y);     term.write("|")
            term.setCursorPos(ic._x - 1, ic._y + 1); term.write("|")
            term.setCursorPos(ic._x + 2, ic._y + 1); term.write("|")
            term.setCursorPos(ic._x - 1, ic._y + 2); term.write("+--+")
        end
        -- подпись: центрируем в ячейке (CELL_W), а не вокруг иконки (ICON_W=2),
        -- иначе длинные подписи в крайних колонках уходят за экран.
        term.setBackgroundColor(th.desktop); term.setTextColor(colors.white)
        local label = text.ellipsize(ic.label, CELL_W - 2)
        local cellLeft = ic._x - 1     -- ic._x = 2 + col*CELL_W → cellLeft = 1 + col*CELL_W
        local lx = cellLeft + math.floor((CELL_W - text.len(label)) / 2)
        if lx < 1 then lx = 1 end
        term.setCursorPos(lx, ic._y + 2); term.write(label)
    end
    taskbar.draw()
end

local function iconAt(mx, my)
    for i, ic in ipairs(ICONS) do
        if ic._x and mx >= ic._x and mx <= ic._x + ic._w - 1
           and my >= ic._y and my <= ic._y + ic._h - 1 then
            return ic, i
        end
    end
    return nil
end

--------------------------------------------------------------
-- Start-меню и контекстные меню
--------------------------------------------------------------
local function startMenu(user)
    local sw, sh = term.getSize()
    local items = {
        { label = "Терминал",    action = function() runApp("terminal", user, "Терминал") end },
        { label = "Файлы",       action = function() runApp("filemanager", user, "Файлы") end },
        { label = "Настройки",   action = function() runApp("settings", user, "Настройки") end },
        { label = "Калькулятор", action = function() runApp("calc", user, "Калькулятор") end },
        { label = "Часы",        action = function() runApp("clock", user, "Часы") end },
        { label = "Змейка",      action = function() runApp("snake", user, "Змейка") end },
        { label = "Paint",       action = function() runApp("paint", user, "Paint") end },
        { label = "Чат (сеть)",  action = function() runApp("chat", user, "Чат") end },
        { label = "─────────",   action = function() end },
        { label = "Выход",       action = function() _G._znatokos_exit = true end },
        { label = "Reboot",      action = function() os.reboot() end },
        { label = "Shutdown",    action = function() os.shutdown() end },
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
                m:event(ev); return
            else
                return
            end
        elseif ev[1] == "key" and (ev[2] == keys.escape) then
            return
        else
            m:event(ev)
            if ev[1] == "key" and ev[2] == keys.enter then return end
        end
    end
end

local function iconContextMenu(user, ic, x, y)
    local items = {
        { label = "Открыть",    action = function() runApp(ic.app, user, ic.label) end },
        { label = "Свойства",   action = function()
            dialog.message("Свойства", "Название: " .. ic.label .. "\nПриложение: " .. ic.app)
        end },
    }
    local m = widgets.menu({ x = x, y = y, items = items })
    m:draw(term)
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if mx >= m.x and mx <= m.x + m.w - 1 and my >= m.y and my <= m.y + m.h - 1 then
                m:event(ev); return
            else return end
        elseif ev[1] == "key" and ev[2] == keys.escape then return
        elseif ev[1] == "key" and ev[2] == keys.enter then m:event(ev); return
        else m:event(ev) end
    end
end

local function desktopContextMenu(user, x, y)
    local items = {
        { label = "Обновить",           action = function() drawIcons(user) end },
        { label = "Видимый курсор: " .. (pointer.isEnabled() and "Вкл" or "Выкл"),
          action = function() pointer.setEnabled(not pointer.isEnabled()) end },
        { label = "Настройки",          action = function() runApp("settings", user, "Настройки") end },
    }
    local m = widgets.menu({ x = x, y = y, items = items })
    m:draw(term)
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if mx >= m.x and mx <= m.x + m.w - 1 and my >= m.y and my <= m.y + m.h - 1 then
                m:event(ev); drawIcons(user); return
            else return end
        elseif ev[1] == "key" and ev[2] == keys.escape then return
        elseif ev[1] == "key" and ev[2] == keys.enter then m:event(ev); drawIcons(user); return
        else m:event(ev) end
    end
end

--------------------------------------------------------------
-- focus-ring навигация по иконкам
--------------------------------------------------------------
local function iconFocusMove(direction)
    local cols
    do
        local sw = term.getSize()
        cols = math.max(1, math.floor((sw - 2) / CELL_W))
    end
    local new = focusedIconIdx
    if direction == "right" then new = new + 1
    elseif direction == "left" then new = new - 1
    elseif direction == "down" then new = new + cols
    elseif direction == "up" then new = new - cols
    end
    if new >= 1 and new <= #ICONS then focusedIconIdx = new end
end

--------------------------------------------------------------
-- основной цикл
--------------------------------------------------------------
function M.run(user)
    _G._znatokos_exit = false
    rebuildIcons(user)
    drawIcons(user)

    -- Компактная панель на встроенном экране (если OS на мониторе)
    local ok_d, dash = pcall(znatokos.use, "ui/builtin_dashboard")
    if ok_d and dash.start then dash.start() end

    -- фоновая задача: часы в taskbar
    sched.spawn({
        name = "taskbar-clock", owner = user.user,
        fn = function()
            while true do
                sleep(1)
                if _G._znatokos_exit then return end
                pcall(taskbar.draw)
            end
        end,
    })

    -- обработчик onClose окон — просто destroy
    wm.setOnClose(function(id) end)

    sched.spawn({
        name = "desktop", owner = user.user,
        fn = function()
            while not _G._znatokos_exit do
                taskbar.draw()
                local ev = { os.pullEvent() }
                if ev[1] == "mouse_click" then
                    local btn, mx, my = ev[2], ev[3], ev[4]
                    pointer.onMouseClick()
                    -- Chrome-клики обрабатывает scheduler.
                    -- Сюда (desktop = задача без окна) приходят только клики
                    -- в пустые зоны (taskbar, иконки, пустой фон).
                    local tb = taskbar.handleClick(mx, my)
                    if tb == "start" then
                        startMenu(user); drawIcons(user); wm.redrawAll()
                    elseif tb == "clock" then
                        dialog.message("Часы", textutils.formatTime(os.time(), true)
                            .. "\nДень: " .. os.day())
                        drawIcons(user); wm.redrawAll()
                    elseif tb == "window" then
                        -- focus уже сделан в taskbar
                    else
                        local ic, idx = iconAt(mx, my)
                        if ic then
                            focusedIconIdx = idx
                            if btn == 1 then
                                runApp(ic.app, user, ic.label)
                            elseif btn == 2 then
                                iconContextMenu(user, ic, mx, my)
                                drawIcons(user); wm.redrawAll()
                            end
                        elseif btn == 2 then
                            desktopContextMenu(user, mx, my); wm.redrawAll()
                        end
                    end
                elseif ev[1] == "key" then
                    local k = ev[2]
                    if pointer.isEnabled() and pointer.handleKey(k, false) then
                        -- handled
                    elseif k == keys.f10 then
                        startMenu(user); drawIcons(user); wm.redrawAll()
                    elseif k == keys.tab then
                        if #wm.list() > 0 then wm.nextWindow()
                        else
                            focusedIconIdx = (focusedIconIdx % #ICONS) + 1
                            drawIcons(user)
                        end
                    elseif k == keys.up    then iconFocusMove("up"); drawIcons(user)
                    elseif k == keys.down  then iconFocusMove("down"); drawIcons(user)
                    elseif k == keys.left  then iconFocusMove("left"); drawIcons(user)
                    elseif k == keys.right then iconFocusMove("right"); drawIcons(user)
                    elseif k == keys.enter or k == keys.space then
                        local ic = ICONS[focusedIconIdx]
                        if ic then runApp(ic.app, user, ic.label) end
                    end
                elseif ev[1] == "znatokos:redraw" then
                    drawIcons(user); wm.redrawAll()
                elseif ev[1] == "znatokos:resize" or ev[1] == "term_resize" then
                    wm.reflow()
                    drawIcons(user); wm.redrawAll()
                end
            end
        end,
    })

    sched.run()
end

return M
