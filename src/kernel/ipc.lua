-- Простая IPC: очереди сообщений между pid.
-- Реализация через os.queueEvent("znatokos:ipc", to, from, msg).
-- Получатель ждёт события фильтром на to == свой pid.
local M = {}

function M.send(from_pid, to_pid, msg)
    os.queueEvent("znatokos:ipc", to_pid, from_pid, msg)
end

function M.broadcast(from_pid, msg)
    os.queueEvent("znatokos:ipc", "*", from_pid, msg)
end

function M.recv(self_pid, timeout)
    local timer
    if timeout then timer = os.startTimer(timeout) end
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "znatokos:ipc" and (ev[2] == self_pid or ev[2] == "*") then
            if timer then os.cancelTimer(timer) end
            return ev[4], ev[3]   -- msg, from
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil, nil
        end
    end
end

return M
