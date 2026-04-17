-- Планировщик задач. Каждая задача — корутина, зарегистрированная с pid.
-- События фильтруются: задача видит либо свои направленные события
-- (mouse_* — только если клик в её окне; ipc — по pid), либо глобальные
-- (timer, char, key — все или по фокусу).
local log = znatokos.use("kernel/log")
local wm  = znatokos.use("kernel/window")

local M = {}
local tasks = {}
local nextPid = 1
local running = false

local function matchEvent(task, ev)
    local name = ev[1]
    if name == "terminate" then return true end
    if name == "znatokos:ipc" then
        return ev[2] == task.pid or ev[2] == "*"
    end
    if name == "char" or name == "key" or name == "key_up" or name == "paste" then
        -- клавиатурные события идут в фокусное окно
        local f = wm.getFocused()
        return f and task.window and f.id == task.window.id
    end
    if name == "mouse_click" or name == "mouse_drag" or name == "mouse_up" or name == "mouse_scroll" then
        -- мышь — в окно под курсором
        if not task.window or not task.window.visible then return false end
        local x, y = ev[3], ev[4]
        local w = task.window
        return x >= w.x and x <= w.x + w.w - 1 and y >= w.y and y <= w.y + w.h - 1
    end
    if name == "timer" or name == "alarm" or name == "redstone" then
        return true
    end
    -- системные события (peripheral, modem_message, rednet_message...) раздаём всем
    return true
end

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
    -- Первый шаг запуска
    local ok, err = coroutine.resume(task.co, table.unpack(opts.args or {}))
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
    local t = tasks[pid]; if not t then return false end
    os.queueEvent("terminate_pid", pid)
    tasks[pid] = nil
    if t.window then
        wm.destroy(t.window.id)
    end
    log.info(("kill pid=%d"):format(pid))
    return true
end

function M.list()
    local arr = {}
    for _, t in pairs(tasks) do arr[#arr + 1] = t end
    table.sort(arr, function(a, b) return a.pid < b.pid end)
    return arr
end

function M.get(pid) return tasks[pid] end

function M.count()
    local n = 0
    for _ in pairs(tasks) do n = n + 1 end
    return n
end

-- Основной цикл планировщика. Блокирующий.
function M.run()
    running = true
    while running and M.count() > 0 do
        local ev = { os.pullEventRaw() }
        if ev[1] == "terminate" then
            running = false
            break
        end
        if ev[1] == "terminate_pid" then
            -- kill одного task — уже обработано в M.kill
        else
            for pid, task in pairs(tasks) do
                if matchEvent(task, ev) and (task.filter == nil or task.filter == ev[1] or ev[1] == "terminate") then
                    local ok, err = coroutine.resume(task.co, table.unpack(ev))
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
