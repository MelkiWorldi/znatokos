-- Планировщик задач. Каждая задача — корутина с pid.
-- События фильтруются по окну/фокусу. Оконное hit-test учитывает chrome.
local log = znatokos.use("kernel/log")
local wm  = znatokos.use("kernel/window")

local M = {}
local tasks = {}
local nextPid = 1
local running = false

-- Мышиные события
local MOUSE_EVENTS = {
    mouse_click = true, mouse_drag = true, mouse_up = true, mouse_scroll = true,
}
-- События клавиатуры
local KEY_EVENTS = {
    char = true, key = true, key_up = true, paste = true,
}
-- Системные события, которые раздаём всем
local BROADCAST_EVENTS = {
    terminate = true, timer = true, alarm = true, redstone = true,
    peripheral = true, peripheral_detach = true, rednet_message = true,
    modem_message = true, ["znatokos:resize"] = true, term_resize = true,
    monitor_resize = true,
}

local function hitWindow(x, y)
    local hit = nil
    for _, ow in pairs(wm.list()) do
        if ow.visible and x >= ow.x and x <= ow.x + ow.w - 1
           and y >= ow.y and y <= ow.y + ow.h - 1 then
            hit = ow
        end
    end
    return hit
end

local function matchEvent(task, ev)
    local name = ev[1]
    if name == "terminate" then return true end
    if name == "znatokos:ipc" then
        return ev[2] == task.pid or ev[2] == "*"
    end
    if name == "znatokos:redraw" then
        return not task.window   -- только desktop
    end
    if name == "znatokos:resize" or name == "term_resize" or name == "monitor_resize" then
        return true   -- всем — пусть сами решают перерисоваться
    end
    if KEY_EVENTS[name] then
        local f = wm.getFocused()
        if task.window then
            return f and f.id == task.window.id
        else
            -- desktop (без окна) получает клавиши только когда нет фокусного окна
            return f == nil
        end
    end
    if MOUSE_EVENTS[name] then
        local x, y = ev[3], ev[4]
        local hit = hitWindow(x, y)
        if task.window then
            return hit and task.window.id == hit.id
        else
            return hit == nil
        end
    end
    if BROADCAST_EVENTS[name] then return true end
    return true
end

--------------------------------------------------------------
-- Управление term.redirect при resume
--------------------------------------------------------------
local nativeTerm = term.current()
function M.setNativeTerm(t) nativeTerm = t end
function M.getNativeTerm() return nativeTerm end

local function resumeTask(task, ...)
    local target = task.window and task.window.win or nativeTerm
    local prev = term.redirect(target)
    local ok, err = coroutine.resume(task.co, ...)
    term.redirect(prev)
    return ok, err
end

--------------------------------------------------------------
-- spawn / kill
--------------------------------------------------------------
function M.spawn(opts)
    local pid = nextPid; nextPid = nextPid + 1
    local task = {
        pid = pid,
        name = opts.name or ("task-" .. pid),
        window = opts.window,
        owner = opts.owner or "root",
        status = "ready",
        filter = nil,
        co = coroutine.create(opts.fn),
        started = os.clock(),
    }
    tasks[pid] = task
    log.info(("spawn pid=%d name=%s"):format(pid, task.name))
    local ok, err = resumeTask(task, table.unpack(opts.args or {}))
    if not ok then
        task.status = "error"
        log.error(("pid=%d error: %s"):format(pid, tostring(err)))
        tasks[pid] = nil
        return nil, err
    end
    task.filter = err
    task.status = coroutine.status(task.co) == "dead" and "dead" or "running"
    if task.status == "dead" then tasks[pid] = nil end
    return pid
end

function M.kill(pid)
    if not tasks[pid] then return false end
    os.queueEvent("terminate_pid", pid)
    return true
end

function M.list()
    local arr = {}
    for _, t in pairs(tasks) do arr[#arr + 1] = t end
    table.sort(arr, function(a, b) return a.pid < b.pid end)
    return arr
end
function M.get(pid) return tasks[pid] end
function M.count() local n = 0; for _ in pairs(tasks) do n = n + 1 end; return n end

-- Убить задачу, у которой есть данное окно
function M.killByWindow(windowId)
    for pid, t in pairs(tasks) do
        if t.window and t.window.id == windowId then
            M.kill(pid); return true
        end
    end
    return false
end

--------------------------------------------------------------
-- Основной цикл планировщика
--------------------------------------------------------------
function M.run()
    running = true
    while running and M.count() > 0 do
        local ev = { os.pullEventRaw() }
        if ev[1] == "terminate" then running = false; break end

        -- monitor_touch (правый клик по монитору) = mouse_click кнопкой 1
        if ev[1] == "monitor_touch" then
            ev = { "mouse_click", 1, ev[3], ev[4] }
        end

        -- peripheral / peripheral_detach передаём display для hot-plug.
        -- monitor_resize также идёт в display, чтобы переопределить размер plane.
        if ev[1] == "peripheral" or ev[1] == "peripheral_detach"
           or ev[1] == "monitor_resize" then
            local ok, display = pcall(znatokos.use, "kernel/display")
            if ok and display.onPeripheralEvent then
                pcall(display.onPeripheralEvent, ev[1], ev[2])
            end
        end

        -- term_resize / monitor_resize — поднимаем znatokos:resize
        if ev[1] == "term_resize" or ev[1] == "monitor_resize" then
            os.queueEvent("znatokos:resize")
        end

        -- Перехват кликов на chrome окна: [X], title (drag), frame (focus).
        -- Content-клики идут дальше в app как обычно.
        if ev[1] == "mouse_click" and ev[2] == 1 then
            local w, hitType = wm.hitTest(ev[3], ev[4])
            if w then
                if hitType == "close" and w.closable then
                    wm.requestClose(w.id); ev = { "__swallowed__" }
                elseif hitType == "title" then
                    wm.focus(w.id); wm.beginDrag(w.id, ev[3], ev[4])
                    ev = { "__swallowed__" }
                elseif hitType == "frame" then
                    wm.focus(w.id); ev = { "__swallowed__" }
                elseif hitType == "content" then
                    wm.focus(w.id)   -- клик в контент = тоже focus
                end
            end
        elseif ev[1] == "mouse_drag" and wm.isDragging() then
            wm.updateDrag(ev[3], ev[4]); ev = { "__swallowed__" }
        elseif ev[1] == "mouse_up" and wm.isDragging() then
            wm.endDrag()
        end

        if ev[1] == "__swallowed__" then
            -- событие обработано window manager'ом, никому не передаём
        elseif ev[1] == "terminate_pid" then
            local pid = ev[2]
            local t = tasks[pid]
            if t then
                if t.window then wm.destroy(t.window.id) end
                if coroutine.status(t.co) == "suspended" then
                    pcall(resumeTask, t, "terminate")
                end
                tasks[pid] = nil
                log.info(("killed pid=%d"):format(pid))
            end
        else
            for pid, task in pairs(tasks) do
                if matchEvent(task, ev)
                   and (task.filter == nil or task.filter == ev[1] or ev[1] == "terminate") then
                    -- Для задач с окном трансформируем координаты мыши в
                    -- локальные координаты содержимого окна (с учётом chrome).
                    local evToSend = ev
                    if task.window and MOUSE_EVENTS[ev[1]] then
                        local w = task.window
                        local offX = w.hasChrome and 1 or 0
                        local offY = w.hasChrome and 1 or 0
                        evToSend = {
                            ev[1], ev[2],
                            ev[3] - w.x - offX + 1,
                            ev[4] - w.y - offY + 1,
                        }
                        if ev[5] ~= nil then evToSend[5] = ev[5] end
                    end
                    local ok, err = resumeTask(task, table.unpack(evToSend))
                    if not ok then
                        log.error(("pid=%d crash: %s"):format(pid, tostring(err)))
                        if task.window then wm.destroy(task.window.id) end
                        tasks[pid] = nil
                    else
                        task.filter = err
                        if coroutine.status(task.co) == "dead" then
                            log.info(("exit pid=%d"):format(pid))
                            if task.window then wm.destroy(task.window.id) end
                            tasks[pid] = nil
                        end
                    end
                end
            end
        end
    end
end

function M.stop() running = false end

return M
