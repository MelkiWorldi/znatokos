-- Discovery-слой ЗнатокOS.
-- Периодически рассылает hello-фреймы по rednet и ведёт таблицу peers.
-- Протокол фрейма: rednet.broadcast("znatokos.discovery",
--     { id=<node.id>, name=<node.name>, role=<node.role>, ts=<epoch> })

local M = {}

-- Безопасный require: если модуль ещё не готов, возвращаем nil.
local function safeUse(path)
    local ok, mod = pcall(znatokos.use, path)
    if ok then return mod end
    return nil
end

local net   = safeUse("net/rednet")
local node  = safeUse("kernel/node")
local log   = safeUse("kernel/log")
local sched = safeUse("kernel/scheduler")

-- Параметры таймингов (секунды).
local HELLO_INTERVAL = 30   -- как часто шлём hello
local PEER_TIMEOUT   = 90   -- через сколько считаем узел offline
local TICK           = 1    -- как часто проверяем просрочку

-- Локальное состояние — не в _G.
local peers = {}          -- [znatokId] = {id, name, role, last_seen, computer_id}
local last_announce = 0   -- время последнего своего hello (в сек, os.clock)

-- Текущее epoch-время в секундах.
local function nowSec()
    return os.epoch("utc") / 1000
end

-- Возвращает собственный znatokId или nil если node недоступна.
local function ownId()
    if not node or not node.getId then return nil end
    local ok, id = pcall(node.getId)
    if ok then return id end
    return nil
end

-- Разовый broadcast hello-фрейма.
function M.announce()
    if not net or not node then return false, "сеть или node недоступны" end
    local ok1, id   = pcall(node.getId)
    local ok2, name = pcall(node.getName)
    local ok3, role = pcall(node.getRole)
    if not (ok1 and ok2 and ok3) then return false, "node не инициализирован" end
    local payload = {
        id   = id,
        name = name,
        role = role,
        ts   = nowSec(),
    }
    local ok = net.broadcast("znatokos.discovery", payload)
    last_announce = os.clock()
    return ok
end

-- Снимок списка известных узлов (массив).
function M.peers()
    local now = nowSec()
    local arr = {}
    for _, p in pairs(peers) do
        arr[#arr + 1] = {
            id          = p.id,
            name        = p.name,
            role        = p.role,
            last_seen   = p.last_seen,
            computer_id = p.computer_id,
            online      = (now - p.last_seen) <= PEER_TIMEOUT,
        }
    end
    table.sort(arr, function(a, b) return (a.name or "") < (b.name or "") end)
    return arr
end

-- Поиск по имени — возвращает computer_id (для rednet.send) или nil.
function M.find(name)
    for _, p in pairs(peers) do
        if p.name == name then return p.computer_id end
    end
    return nil
end

-- Поиск по znatokId — возвращает computer_id или nil.
function M.findByNodeId(znatokId)
    local p = peers[znatokId]
    if p then return p.computer_id end
    return nil
end

-- Обработка одного hello-фрейма.
-- msg — распакованный envelope rednet.receive (msg.proto/payload/from),
-- senderCid — computer id отправителя из rednet.
local function handleHello(msg, senderCid)
    if type(msg) ~= "table" or msg.proto ~= "znatokos.discovery" then return end
    local p = msg.payload
    if type(p) ~= "table" or not p.id or not p.name then return end
    local own = ownId()
    if own and p.id == own then return end  -- игнорим сами себя

    local existing = peers[p.id]
    peers[p.id] = {
        id          = p.id,
        name        = p.name,
        role        = p.role,
        last_seen   = nowSec(),
        computer_id = senderCid,
    }
    if not existing then
        if log and log.info then
            pcall(log.info, "discovery: новый пир " .. tostring(p.name) ..
                  " (" .. tostring(p.id) .. ") cid=" .. tostring(senderCid))
        end
        os.queueEvent("znatokos:peer_up", p.id, p.name, senderCid)
    end
end

-- Проверка просрочки — удаляем offline-пиров и эмиттим peer_down.
local function expireStale()
    local now = nowSec()
    local toRemove = {}
    for id, p in pairs(peers) do
        if (now - p.last_seen) > PEER_TIMEOUT then
            toRemove[#toRemove + 1] = id
        end
    end
    for _, id in ipairs(toRemove) do
        local p = peers[id]
        peers[id] = nil
        if log and log.info then
            pcall(log.info, "discovery: пир offline " .. tostring(p.name) ..
                  " (" .. tostring(id) .. ")")
        end
        os.queueEvent("znatokos:peer_down", id, p.name, p.computer_id)
    end
end

-- Основной event-loop сервиса.
-- Использует parallel.waitForAny для чередования приёма и тика.
function M.runService()
    if not net then
        if log and log.warn then pcall(log.warn, "discovery: rednet недоступен") end
        return
    end
    -- гарантируем, что модемы открыты
    pcall(net.ensureOpen)

    -- Первое объявление сразу.
    pcall(M.announce)

    local function receiver()
        while true do
            -- net.receive возвращает (msg, id, err); фильтр по proto.
            local msg, senderCid = net.receive("znatokos.discovery")
            if msg then
                handleHello(msg, senderCid)
            else
                -- если rednet ещё не готов — подождём секунду
                sleep(1)
            end
        end
    end

    local function ticker()
        while true do
            sleep(TICK)
            expireStale()
            if (os.clock() - last_announce) >= HELLO_INTERVAL then
                pcall(M.announce)
            end
        end
    end

    parallel.waitForAny(receiver, ticker)
end

-- Спавн сервиса через kernel/scheduler. Возвращает pid или nil.
function M.startService()
    if not sched or not sched.spawn then return nil, "планировщик недоступен" end
    local pid = sched.spawn({
        name  = "discovery",
        owner = "root",
        fn    = function()
            -- изолируем в pcall — падение сервиса не должно ломать планировщик
            local ok, err = pcall(M.runService)
            if (not ok) and log and log.error then
                pcall(log.error, "discovery: сервис упал: " .. tostring(err))
            end
        end,
    })
    return pid
end

return M
