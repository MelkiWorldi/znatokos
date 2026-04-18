-- Песочница для приложений ZnatokOS.
-- Отвечает за две вещи:
--   1) Хранение granted/denied прав (capabilities) для каждого приложения
--      в /znatokos/etc/permissions.db (Lua-сериализованная таблица).
--   2) Построение изолированной _ENV таблицы для запуска приложения —
--      пробрасывает только безопасные глобалы и те API, на которые
--      приложению выданы capabilities.
--
-- Компромисс по peripheral: CC:Tweaked не различает типы peripheral'ов на
-- уровне API, поэтому любая из periph.* capability открывает доступ ко всему
-- peripheral-API. В описании каждой cap явно указано, что именно допускается.

local paths        = znatokos.use("fs/paths")
local capabilities = znatokos.use("kernel/capabilities")
local log          = znatokos.use("kernel/log")

local M = {}

-- ----------------------------------------------------------------------
-- Persistence прав
-- ----------------------------------------------------------------------

-- Путь к БД прав. Сделан локальной переменной, чтобы тесты могли
-- подменить его через M._setDBPath.
local DB_PATH = paths.ETC .. "/permissions.db"

function M._setDBPath(p)
    DB_PATH = p
end

function M._getDBPath()
    return DB_PATH
end

local function ensureDir(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function loadDB()
    if not fs.exists(DB_PATH) then return {} end
    local f = fs.open(DB_PATH, "r")
    if not f then return {} end
    local data = f.readAll(); f.close()
    local ok, t = pcall(textutils.unserialize, data)
    if ok and type(t) == "table" then return t end
    return {}
end

local function saveDB(db)
    ensureDir(DB_PATH)
    local f = fs.open(DB_PATH, "w")
    if not f then
        log.error("sandbox: не удалось открыть на запись " .. DB_PATH)
        return false
    end
    f.write(textutils.serialize(db)); f.close()
    return true
end

-- Получить таблицу {capId = bool} для приложения
function M.permissionsGet(appId)
    local db = loadDB()
    local entry = db[appId]
    if type(entry) ~= "table" then return {} end
    -- возвращаем копию чтобы внешний код не модифицировал БД
    local copy = {}
    for k, v in pairs(entry) do copy[k] = v end
    return copy
end

-- Сохранить allow (true/false) для пары appId+capId.
function M.permissionsGrant(appId, capId, allow)
    if type(appId) ~= "string" or appId == "" then
        return false, "appId обязателен"
    end
    if not capabilities.isValid(capId) then
        return false, "неизвестная capability: " .. tostring(capId)
    end
    local db = loadDB()
    db[appId] = db[appId] or {}
    db[appId][capId] = allow and true or false
    if not saveDB(db) then return false, "не удалось сохранить БД" end
    log.info(("sandbox: %s -> %s = %s"):format(appId, capId, tostring(allow and true or false)))
    return true
end

-- Удалить все записи для приложения (например при uninstall)
function M.permissionsClear(appId)
    local db = loadDB()
    if db[appId] == nil then return true end
    db[appId] = nil
    saveDB(db)
    log.info("sandbox: очищены права " .. tostring(appId))
    return true
end

-- true только если есть явная запись true
function M.permissionsHas(appId, capId)
    local entry = M.permissionsGet(appId)
    return entry[capId] == true
end

-- Массив capId которые запрошены но НЕ granted (true).
-- Записи с явным false считаются "решёнными" и не попадают в missing.
function M.permissionsMissing(appId, requestedCaps)
    local entry = M.permissionsGet(appId)
    local out = {}
    if type(requestedCaps) ~= "table" then return out end
    for i = 1, #requestedCaps do
        local c = requestedCaps[i]
        if entry[c] ~= true and entry[c] ~= false then
            out[#out + 1] = c
        end
    end
    return out
end

-- Массив capId которые вообще без записи (ни true ни false).
-- Используется для prompt'а пользователю при первом запуске.
function M.permissionsUnknown(appId, requestedCaps)
    local entry = M.permissionsGet(appId)
    local out = {}
    if type(requestedCaps) ~= "table" then return out end
    for i = 1, #requestedCaps do
        local c = requestedCaps[i]
        if entry[c] == nil then out[#out + 1] = c end
    end
    return out
end

-- ----------------------------------------------------------------------
-- Построение sandbox _ENV
-- ----------------------------------------------------------------------

-- Хелпер: в массиве caps содержится capId?
local function hasCap(caps, capId)
    if type(caps) ~= "table" then return false end
    for i = 1, #caps do
        if caps[i] == capId then return true end
    end
    return false
end

-- Любая ли из periph.* capabilities выдана?
local function hasAnyPeriph(caps)
    if type(caps) ~= "table" then return false end
    for i = 1, #caps do
        local c = caps[i]
        if type(c) == "string" and c:sub(1, 7) == "periph." then return true end
    end
    return false
end

-- Возвращает true если fs.all выдан (хелпер для внешних модулей)
function M.allowRoot(caps)
    return hasCap(caps, "fs.all")
end

-- Нормализация пути: убираем ведущие "/" и схлопываем через fs.combine("/", p)
local function normalize(p)
    if type(p) ~= "string" then return nil end
    if p == "" then return "/" end
    if p:sub(1, 1) ~= "/" then p = "/" .. p end
    return fs.combine("/", p)
end

-- Возвращает абсолютный путь внутри home или nil если путь вырывается наружу.
local function resolveHome(homeDir, path)
    if type(path) ~= "string" then return nil end
    local home = normalize(homeDir)
    local abs
    if path:sub(1, 1) == "/" then
        abs = normalize(path)
    else
        -- относительный: склеиваем с home
        abs = normalize(fs.combine(home, path))
    end
    if not abs then return nil end
    -- проверяем что абсолютный путь внутри home
    if abs == home then return abs end
    if abs:sub(1, #home + 1) == home .. "/" then return abs end
    return nil
end

-- Построить fs-прокси, ограничивающий доступ только home-директорией.
-- Все функции, у которых первый аргумент — путь, проверяют его.
-- Вторые-аргумент-пути (move/copy) тоже проверяются.
local function buildFsHome(homeDir)
    local home = normalize(homeDir)
    -- создадим home если его нет
    if not fs.exists(home) then pcall(fs.makeDir, home) end

    local denied = function(path)
        return nil, "Доступ запрещён: " .. tostring(path) .. " вне " .. home
    end

    local function check(path)
        local r = resolveHome(home, path)
        if not r then return nil, "Доступ запрещён: " .. tostring(path) .. " вне " .. home end
        return r
    end

    local proxy = {}

    function proxy.open(path, mode)
        local r, err = check(path); if not r then return nil, err end
        return fs.open(r, mode)
    end

    function proxy.exists(path)
        local r = check(path); if not r then return false end
        return fs.exists(r)
    end

    function proxy.isDir(path)
        local r = check(path); if not r then return false end
        return fs.isDir(r)
    end

    function proxy.isReadOnly(path)
        local r = check(path); if not r then return true end
        return fs.isReadOnly(r)
    end

    function proxy.list(path)
        local r, err = check(path); if not r then error(err, 2) end
        return fs.list(r)
    end

    function proxy.makeDir(path)
        local r, err = check(path); if not r then error(err, 2) end
        return fs.makeDir(r)
    end

    function proxy.delete(path)
        local r, err = check(path); if not r then error(err, 2) end
        return fs.delete(r)
    end

    function proxy.move(src, dst)
        local rs, es = check(src); if not rs then error(es, 2) end
        local rd, ed = check(dst); if not rd then error(ed, 2) end
        return fs.move(rs, rd)
    end

    function proxy.copy(src, dst)
        local rs, es = check(src); if not rs then error(es, 2) end
        local rd, ed = check(dst); if not rd then error(ed, 2) end
        return fs.copy(rs, rd)
    end

    function proxy.getSize(path)
        local r, err = check(path); if not r then error(err, 2) end
        return fs.getSize(r)
    end

    function proxy.attributes(path)
        local r, err = check(path); if not r then error(err, 2) end
        if fs.attributes then return fs.attributes(r) end
        return nil
    end

    -- "безопасные" комбинаторы путей — не трогают fs, но полезны приложению
    function proxy.combine(a, b) return fs.combine(a, b) end
    function proxy.getName(p)    return fs.getName(p) end
    function proxy.getDir(p)     return fs.getDir(p) end

    -- Публикуем директорию home в качестве "корня" для приложения
    proxy._home = home

    return proxy
end

-- read-only подмножество os
local function buildOs(caps)
    local safe = {
        time           = os.time,
        clock          = os.clock,
        date           = os.date,
        epoch          = os.epoch,
        getComputerID  = os.getComputerID,
        computerID     = os.getComputerID,
        getComputerLabel = os.getComputerLabel,
        day            = os.day,
        queueEvent     = os.queueEvent,
        pullEvent      = os.pullEvent,
        pullEventRaw   = os.pullEventRaw,
        startTimer     = os.startTimer,
        cancelTimer    = os.cancelTimer,
        sleep          = os.sleep,
        version        = os.version,
    }
    if hasCap(caps, "system.shutdown") then
        safe.shutdown = os.shutdown
        safe.reboot   = os.reboot
    end
    return safe
end

-- Построить ограниченный peripheral API (если хоть какая-то periph.* есть)
local function buildPeripheral(caps)
    if not hasAnyPeriph(caps) then return nil end
    -- periph.list даёт только перечисление; остальные periph.* — полный доступ
    if hasCap(caps, "periph.list")
        or hasCap(caps, "periph.redstone")
        or hasCap(caps, "periph.inventory")
        or hasCap(caps, "periph.advanced")
        or hasCap(caps, "periph.bridge")
        or hasCap(caps, "periph.logistics")
    then
        -- Компромисс: если выдана хотя бы одна "содержательная" periph.*,
        -- даём полный peripheral (API не различает типы).
        -- Для чистого periph.list — только перечисление.
        local full = hasCap(caps, "periph.redstone")
                  or hasCap(caps, "periph.inventory")
                  or hasCap(caps, "periph.advanced")
                  or hasCap(caps, "periph.bridge")
                  or hasCap(caps, "periph.logistics")
        if full then
            return peripheral
        else
            -- только list
            return {
                getNames = peripheral.getNames,
                getType  = peripheral.getType,
                isPresent = peripheral.isPresent,
            }
        end
    end
    return nil
end

-- Фильтр: оставляем только cap'ы из списка caps, которые реально имеют true
-- в permissions БД для appId. Это вспомогательная функция — caller может
-- сам передавать уже отфильтрованный список в M.build(opts).
function M.effectiveCaps(appId, requestedCaps)
    local entry = M.permissionsGet(appId)
    local out = {}
    if type(requestedCaps) ~= "table" then return out end
    for i = 1, #requestedCaps do
        local c = requestedCaps[i]
        if entry[c] == true then out[#out + 1] = c end
    end
    return out
end

-- Основная функция: построить _ENV для app.
function M.build(opts)
    opts = opts or {}
    local appId   = opts.appId   or "unknown"
    local user    = opts.user    or { user = "guest", home = paths.HOMES .. "/guest" }
    local caps    = opts.caps    or {}
    local appDir  = opts.appDir
    -- window зарезервирован на будущее (scheduler'ом редиректится term)
    local _window = opts.window  -- luacheck: ignore

    local env = {}

    -- Базовые безопасные глобалы
    env.print       = print
    env.write       = write
    env.read        = read
    env.sleep       = sleep
    env.pairs       = pairs
    env.ipairs      = ipairs
    env.next        = next
    env.tostring    = tostring
    env.tonumber    = tonumber
    env.type        = type
    env.select      = select
    env.error       = error
    env.assert      = assert
    env.pcall       = pcall
    env.xpcall      = xpcall
    env.setmetatable = setmetatable
    env.getmetatable = getmetatable
    env.rawget      = rawget
    env.rawset      = rawset
    env.rawequal    = rawequal
    env.rawlen      = rawlen
    env.unpack      = table.unpack or unpack  -- совместимость
    env.string      = string
    env.table       = table
    env.math        = math
    env.coroutine   = coroutine
    env.textutils   = textutils
    env.bit32       = bit32
    env.colors      = colors
    env.colours     = colours or colors
    env.keys        = keys

    env.os          = buildOs(caps)

    -- term выдаётся всегда "как есть" — scheduler уже изолировал окно через redirect.
    env.term        = term

    -- fs:
    if hasCap(caps, "fs.all") then
        env.fs = fs
    elseif hasCap(caps, "fs.home") then
        env.fs = buildFsHome(user.home)
    else
        env.fs = nil
    end

    -- Сеть
    if hasCap(caps, "net.rednet") then env.rednet = rednet end
    if hasCap(caps, "net.http")   then env.http   = http   end

    -- Периферия
    env.peripheral = buildPeripheral(caps)
    if hasCap(caps, "periph.redstone") then
        env.redstone = redstone
        env.rs       = redstone
    end

    -- kernel-подобный API для приложения: use() только из разрешённых каталогов.
    -- Разрешаем приложению грузить только: свой appDir, public sdk (src/sdk/*),
    -- и капабилити-нейтральные модули, если они явно заданы в opts.allowedModules.
    local allowedModules = opts.allowedModules or {}
    local function safeUse(modulePath)
        if type(modulePath) ~= "string" then error("use: ожидается строка", 2) end
        -- ищем сначала в appDir
        if appDir then
            local local1 = fs.combine(appDir, modulePath .. ".lua")
            if fs.exists(local1) then
                local chunk, err = loadfile(local1, "bt", env)
                if not chunk then error("use(" .. modulePath .. "): " .. tostring(err), 2) end
                return chunk()
            end
        end
        -- затем в whitelist
        for i = 1, #allowedModules do
            if allowedModules[i] == modulePath then
                return znatokos.use(modulePath)
            end
        end
        error("use: модуль запрещён: " .. modulePath, 2)
    end

    local kernelTbl = { use = safeUse }
    if hasCap(caps, "kernel.spawn") then
        -- spawn пробрасывается если есть cap
        local sched = znatokos.use("kernel/sched")
        kernelTbl.spawn = sched and sched.spawn
    end
    env.kernel = kernelTbl

    -- znatokos-объект для app
    env.znatokos = {
        VERSION = (_G.znatokos and _G.znatokos.VERSION) or "0.3.0",
        use     = safeUse,
        app     = { id = appId, dir = appDir },
    }

    -- load/loadfile/loadstring: ограничены appDir
    env.load = function(chunk, chunkname, mode, lenv)
        return load(chunk, chunkname, mode or "t", lenv or env)
    end
    env.loadstring = function(chunk, chunkname)
        return load(chunk, chunkname or "=(loadstring)", "t", env)
    end
    env.loadfile = function(path, mode, lenv)
        if type(path) ~= "string" then return nil, "loadfile: ожидается путь" end
        local norm = normalize(path)
        local allowed = false
        if appDir then
            local root = normalize(appDir)
            if norm == root or norm:sub(1, #root + 1) == root .. "/" then
                allowed = true
            end
        end
        if not allowed then
            return nil, "loadfile: путь вне appDir: " .. tostring(path)
        end
        return loadfile(norm, mode or "bt", lenv or env)
    end

    -- require/dofile/package запрещены
    env.require = nil
    env.dofile  = nil
    env.package = nil

    -- _G / _ENV указывают на сам sandbox
    env._G   = env
    env._ENV = env

    return env
end

-- Загрузить entry-скрипт приложения с нужным _ENV.
-- manifest должен иметь поля entry (relative path внутри appDir), id, caps.
function M.loadApp(manifest, opts)
    opts = opts or {}
    local appDir = opts.appDir or manifest.dir
    if not appDir then return nil, "loadApp: не указан appDir" end
    local entry = manifest.entry or "main.lua"
    local entryPath = fs.combine(appDir, entry)
    if not fs.exists(entryPath) then
        return nil, "loadApp: entry не найден: " .. entryPath
    end

    local caps = opts.caps
    if not caps then
        caps = M.effectiveCaps(manifest.id or opts.appId, manifest.caps or {})
    end

    local env = M.build({
        appId          = manifest.id or opts.appId,
        user           = opts.user,
        caps           = caps,
        appDir         = appDir,
        window         = opts.window,
        allowedModules = opts.allowedModules,
    })

    local fn, err = loadfile(entryPath, "bt", env)
    if not fn then return nil, "loadApp: " .. tostring(err) end
    return fn, nil, env
end

return M
