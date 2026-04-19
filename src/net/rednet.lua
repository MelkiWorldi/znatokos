-- Обёртка над rednet. Автоматически открывает все модемы при первом вызове,
-- даёт отправку/приём фреймов с протоколом ЗнатокOS.
local M = {}

-- Всегда сканируем модемы заново: кэш кidleрушился на peripheral_detach.
-- ensureOpen дёшев — проверка через rednet.isOpen + open только если ещё не.
function M.ensureOpen()
    local any = false
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then
                pcall(rednet.open, side)
            end
            if rednet.isOpen(side) then any = true end
        end
    end
    return any
end

function M.id() return os.getComputerID() end

function M.label()
    return os.getComputerLabel() or ("comp-" .. os.getComputerID())
end

function M.send(to, proto, payload)
    if not M.ensureOpen() then return false, "нет модема" end
    local frame = { proto = proto, from = M.id(), to = to, payload = payload,
                    nonce = os.epoch("utc") .. "." .. math.random(1, 1e6) }
    return rednet.send(to, frame, "znatokos")
end

function M.broadcast(proto, payload)
    if not M.ensureOpen() then return false, "нет модема" end
    local frame = { proto = proto, from = M.id(), to = "*", payload = payload,
                    nonce = os.epoch("utc") .. "." .. math.random(1, 1e6) }
    rednet.broadcast(frame, "znatokos")
    return true
end

-- filter: либо строка протокола, либо nil (любой). timeout опционален.
function M.receive(filter, timeout)
    if not M.ensureOpen() then return nil, nil, "нет модема" end
    local deadline = timeout and (os.clock() + timeout) or nil
    while true do
        local remaining = deadline and math.max(0, deadline - os.clock()) or nil
        if deadline and remaining <= 0 then return nil, nil, "timeout" end
        local id, msg = rednet.receive("znatokos", remaining)
        if not id then return nil, nil, "timeout" end
        if type(msg) == "table" and (not filter or msg.proto == filter) then
            return msg, id
        end
    end
end

function M.discover(timeout)
    timeout = timeout or 2
    M.broadcast("znatokos.ping", { who = M.label() })
    local hosts = {}
    local tStart = os.clock()
    while os.clock() - tStart < timeout do
        local msg, id = M.receive("znatokos.pong", timeout - (os.clock() - tStart))
        if not msg then break end
        hosts[#hosts + 1] = { id = id, label = msg.payload and msg.payload.who or "?" }
    end
    return hosts
end

-- Бесконечный цикл откликов на ping. Предназначен для запуска как задача.
function M.pingResponder()
    while true do
        local msg, id = M.receive("znatokos.ping")
        if msg then M.send(id, "znatokos.pong", { who = M.label() }) end
    end
end

return M
