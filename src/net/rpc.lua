-- Простой RPC-слой ZnatokOS поверх net/rednet.
-- Фреймы:
--   { proto="znatokos.rpc", kind="call",  id=<nonce>, method=<str>, args=<array> }
--   { proto="znatokos.rpc", kind="reply", id=<nonce>, result=<any> }
--   { proto="znatokos.rpc", kind="error", id=<nonce>, error=<str> }
--
-- Безопасность здесь не предусмотрена: принимаем вызовы от любого.
-- Подписанные вызовы реализуются поверх (net/remote).

local net = znatokos.use("net/rednet")
local log
do
    local ok, mod = pcall(znatokos.use, "kernel/log")
    if ok then log = mod else
        log = { info = function() end, warn = function() end,
                error = function() end, debug = function() end }
    end
end

local M = {}
local PROTO = "znatokos.rpc"

-- Регистрация методов. handler(args, from) -> result (любое значение).
-- Если handler кидает error — клиенту уйдёт error-фрейм.
local methods = {}

--------------------------------------------------------------
-- Вспомогательные функции для работы с фреймами
--------------------------------------------------------------

-- Генератор уникального nonce: миллисекундный epoch + случайное число.
local function makeNonce()
    return tostring(os.epoch("utc")) .. "." .. tostring(math.random(1, 1e9))
end

-- encodeFrame: формирует Lua-таблицу фрейма (внутренняя функция,
-- доступна для тестов). Валидирует обязательные поля.
function M.encodeFrame(kind, id, extra)
    if kind ~= "call" and kind ~= "reply" and kind ~= "error" then
        error("rpc.encodeFrame: неизвестный kind=" .. tostring(kind))
    end
    if type(id) ~= "string" and type(id) ~= "number" then
        error("rpc.encodeFrame: id обязателен")
    end
    local f = { proto = PROTO, kind = kind, id = id }
    if extra then
        for k, v in pairs(extra) do f[k] = v end
    end
    return f
end

-- decodeFrame: проверяет структуру входящего фрейма. Возвращает
-- (frame, nil) при успехе или (nil, "причина") при невалидном.
function M.decodeFrame(frame)
    if type(frame) ~= "table" then return nil, "не таблица" end
    if frame.proto ~= PROTO then return nil, "чужой proto" end
    local k = frame.kind
    if k ~= "call" and k ~= "reply" and k ~= "error" then
        return nil, "неизвестный kind"
    end
    if frame.id == nil then return nil, "нет id" end
    if k == "call" then
        if type(frame.method) ~= "string" then return nil, "нет method" end
        if frame.args ~= nil and type(frame.args) ~= "table" then
            return nil, "args должен быть массивом"
        end
    end
    return frame, nil
end

--------------------------------------------------------------
-- Регистрация методов
--------------------------------------------------------------

function M.register(method, handler)
    if type(method) ~= "string" or method == "" then
        error("rpc.register: method должен быть непустой строкой")
    end
    if type(handler) ~= "function" then
        error("rpc.register: handler должен быть функцией")
    end
    methods[method] = handler
end

function M.unregister(method)
    methods[method] = nil
end

function M.listMethods()
    local arr = {}
    for k in pairs(methods) do arr[#arr + 1] = k end
    table.sort(arr)
    return arr
end

-- Доступ для тестов/диагностики.
function M._getHandler(method) return methods[method] end

--------------------------------------------------------------
-- Клиентский вызов
--------------------------------------------------------------

-- Резолв target: если число — возвращаем как id; если строка —
-- пытаемся найти через модуль net/discovery (если есть).
local function resolveTarget(target)
    if type(target) == "number" then return target end
    if type(target) ~= "string" then return nil, "unknown target" end
    local ok, disc = pcall(znatokos.use, "net/discovery")
    if not ok or not disc or type(disc.find) ~= "function" then
        return nil, "unknown target"
    end
    local id = disc.find(target)
    if type(id) ~= "number" then return nil, "unknown target" end
    return id
end

-- Отправка call-фрейма и ожидание ответа с тем же id.
function M.call(target, method, args, timeout)
    timeout = timeout or 5
    local id, terr = resolveTarget(target)
    if not id then return nil, terr end

    if not net.ensureOpen() then return nil, "нет модема" end

    local nonce = makeNonce()
    local frame = M.encodeFrame("call", nonce, {
        method = method,
        args = args or {},
    })

    local ok, sendErr = net.send(id, PROTO, frame)
    if not ok then return nil, sendErr or "ошибка отправки" end

    -- Принимаем фреймы с нужным nonce до таймаута.
    -- net.receive сам оборачивает входящее в { proto=..., payload=... },
    -- поэтому вытаскиваем наш rpc-фрейм из payload.
    local deadline = os.clock() + timeout
    while true do
        local remaining = deadline - os.clock()
        if remaining <= 0 then return nil, "timeout" end
        local msg, from, rerr = net.receive(PROTO, remaining)
        if not msg then return nil, rerr or "timeout" end
        local inner = msg.payload
        local fr, derr = M.decodeFrame(inner)
        if fr and fr.id == nonce then
            if fr.kind == "reply" then
                return fr.result, nil
            elseif fr.kind == "error" then
                return nil, fr.error or "remote error"
            end
            -- call с нашим nonce — игнорируем, это эхо/странность
        end
        -- чужой фрейм или наш call — продолжаем ждать
        if derr then log.debug("rpc.call: ignored frame: " .. derr) end
    end
end

--------------------------------------------------------------
-- Серверный цикл
--------------------------------------------------------------

-- Обработать один входящий call-фрейм: запустить handler в pcall,
-- отправить reply или error обратно.
local function handleCall(frame, from)
    local handler = methods[frame.method]
    if not handler then
        net.send(from, PROTO, M.encodeFrame("error", frame.id, {
            error = "unknown method: " .. tostring(frame.method),
        }))
        return
    end
    local ok, result = pcall(handler, frame.args or {}, from)
    if ok then
        net.send(from, PROTO, M.encodeFrame("reply", frame.id, {
            result = result,
        }))
    else
        net.send(from, PROTO, M.encodeFrame("error", frame.id, {
            error = tostring(result),
        }))
    end
end

-- Бесконечный цикл приёма. Запускается как задача через sched.spawn.
function M.runHost()
    if not net.ensureOpen() then
        log.warn("rpc.runHost: нет модема, выход")
        return
    end
    log.info("rpc: host запущен")
    while true do
        local msg, from = net.receive(PROTO)
        if msg and from then
            local fr, derr = M.decodeFrame(msg.payload)
            if fr and fr.kind == "call" then
                local ok, err = pcall(handleCall, fr, from)
                if not ok then
                    log.error("rpc: handleCall crash: " .. tostring(err))
                end
            elseif derr then
                log.debug("rpc: invalid frame from #" .. tostring(from)
                          .. ": " .. derr)
            end
            -- reply/error без активного call — игнорируем
        end
    end
end

-- Спавн хост-задачи через планировщик.
function M.startService()
    local ok, sched = pcall(znatokos.use, "kernel/scheduler")
    if not ok or not sched or not sched.spawn then
        log.warn("rpc.startService: scheduler недоступен")
        return nil, "no scheduler"
    end
    return sched.spawn({ name = "rpc-host", fn = M.runHost })
end

--------------------------------------------------------------
-- Встроенные методы
--------------------------------------------------------------

-- Эхо: возвращает переданные аргументы.
M.register("echo", function(args)
    return args
end)

-- Пинг: простой ответ.
M.register("ping", function()
    return "pong"
end)

-- Инфо: имя/id/роль/версия/uptime. Работает и без kernel/node.
M.register("info", function()
    local info = {
        id      = os.getComputerID(),
        version = _G.znatokos and _G.znatokos.VERSION or "?",
        uptime  = os.clock(),
    }
    local ok, node = pcall(znatokos.use, "kernel/node")
    if ok and node and node.getName then
        info.name = node.getName()
        info.role = node.getRole()
        info.nodeId = node.getId()
    else
        info.name = os.getComputerLabel() or ("comp-" .. info.id)
        info.role = "unknown"
    end
    return info
end)

return M
