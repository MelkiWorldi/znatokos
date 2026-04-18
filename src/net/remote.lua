-- Удалённый shell поверх RPC.
-- shell.exec — RPC-метод, принимает {cmd, sig}, где sig = HMAC(cmd, psk).
-- PSK хранится в /znatokos/etc/remote.key.

local M = {}

-- Безопасная загрузка зависимостей. Если что-то ещё не готово — модуль
-- всё равно грузится, функции вернут "ещё не инициализировано".
local function safeUse(path)
    local ok, mod = pcall(znatokos.use, path)
    if ok then return mod end
    return nil
end

local sha   = safeUse("auth/sha256")
local rpc   = safeUse("net/rpc")
local node  = safeUse("kernel/node")
local paths = safeUse("fs/paths")
local log   = safeUse("kernel/log")

local NOT_READY = "ещё не инициализировано"

-- Путь к PSK-файлу.
local function keyPath()
    if not paths then return "/znatokos/etc/remote.key" end
    return paths.ETC .. "/remote.key"
end

-- Читает PSK, или nil если файла нет.
local function loadKey()
    local p = keyPath()
    if not fs.exists(p) then return nil end
    local f = fs.open(p, "r")
    if not f then return nil end
    local k = f.readAll()
    f.close()
    return k
end

-- HMAC-SHA256 (упрощённый): если есть sha.hmac — используем её,
-- иначе реализуем через стандартную формулу.
local function hmac(msg, key)
    if not sha or not sha.hash then return nil, NOT_READY end
    if sha.hmac then return sha.hmac(msg, key) end
    -- Локальный HMAC-SHA256 поверх sha.hash.
    local blocksize = 64
    key = key or ""
    if #key > blocksize then key = sha.hash(key) end
    if #key < blocksize then key = key .. string.rep("\0", blocksize - #key) end
    local o_pad, i_pad = {}, {}
    for i = 1, blocksize do
        local b = key:byte(i)
        o_pad[i] = string.char(bit32.bxor(b, 0x5c))
        i_pad[i] = string.char(bit32.bxor(b, 0x36))
    end
    local ipad = table.concat(i_pad)
    local opad = table.concat(o_pad)
    return sha.hash(opad .. sha.hash(ipad .. msg))
end

-- Сохраняет новый PSK.
function M.setKey(key)
    local p = keyPath()
    local dir = fs.getDir(p)
    if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(p, "w")
    if not f then return false, "не удалось открыть " .. p end
    f.write(key)
    f.close()
    return true
end

function M.getKey() return loadKey() end

-- Обработчик RPC-метода shell.exec.
-- args = {cmd=..., sig=...}. Возвращает {ok, out, err}.
local function shellExecHandler(args, from)
    if type(args) ~= "table" or type(args.cmd) ~= "string" then
        return nil, "плохой запрос"
    end
    local key = loadKey()
    if not key then return nil, "нет PSK ключа" end
    local expected, herr = hmac(args.cmd, key)
    if not expected then return nil, herr or "hmac error" end
    if expected ~= args.sig then
        if log and log.warn then
            pcall(log.warn, "remote: bad sig from " .. tostring(from))
        end
        return nil, "плохая подпись"
    end

    -- Выполняем команду, перехватываем print.
    local out = {}
    local oldPrint = _G.print
    _G.print = function(...)
        local parts = { ... }
        for i, v in ipairs(parts) do parts[i] = tostring(v) end
        out[#out + 1] = table.concat(parts, "\t")
    end
    local ok, err = pcall(function() shell.run(args.cmd) end)
    _G.print = oldPrint

    if log and log.info then
        pcall(log.info, "remote: exec from " .. tostring(from) ..
              " cmd=" .. args.cmd .. " ok=" .. tostring(ok))
    end
    return {
        ok  = ok,
        out = table.concat(out, "\n"),
        err = ok and nil or tostring(err),
    }
end

-- Регистрирует shell.exec в RPC. Сам rpc-сервис запускается отдельно
-- (boot.lua стартует rpc.startService и discovery.startService).
function M.runHost()
    if not rpc or not rpc.register then
        if log and log.warn then pcall(log.warn, "remote: rpc недоступен") end
        return false, NOT_READY
    end
    local ok, err = pcall(rpc.register, "shell.exec", shellExecHandler)
    if not ok then return false, tostring(err) end
    if log and log.info then pcall(log.info, "remote: shell.exec зарегистрирован") end
    return true
end

-- Отправляет команду на target (znatokId или computer_id — решает rpc.call).
-- Возвращает результат (таблица {ok,out,err}) или nil, err.
function M.sendCmd(target, cmd, timeout)
    if not rpc or not rpc.call then return nil, NOT_READY end
    local key = loadKey()
    if not key then return nil, "нет PSK ключа" end
    local sig, herr = hmac(cmd, key)
    if not sig then return nil, herr or "hmac error" end
    local res, err = rpc.call(target, "shell.exec", {
        cmd = cmd,
        sig = sig,
    }, timeout or 10)
    if not res then return nil, err end
    return res
end

return M
