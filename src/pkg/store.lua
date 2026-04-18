-- HTTP-клиент магазина приложений ZnatokOS.
-- Работает со схемой:
--   GET <base>/index.json
--   GET <base>/apps/<id>/manifest.lua
--   GET <base>/apps/<id>/files/<path>

local paths    = znatokos.use("fs/paths")
local log      = znatokos.use("kernel/log")
local manifest = znatokos.use("pkg/manifest")

local M = {}

-- Значения по умолчанию для конфигурации.
local DEFAULT_CFG = { url = "http://85.239.37.114/store", timeout = 10 }

-- TTL кэша индекса в секундах (5 минут).
local INDEX_CACHE_TTL = 5 * 60
local INDEX_CACHE_PATH = paths.STORE_CACHE .. "/index.json"

-- ----------------------------------------------------------------------
-- Утилиты файловой системы и конфигурации
-- ----------------------------------------------------------------------

local function ensureDir(path)
    if not fs.exists(path) then
        fs.makeDir(path)
    end
end

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local data = f.readAll()
    f.close()
    return data
end

local function writeFile(path, data)
    ensureParent(path)
    local f = fs.open(path, "w")
    if not f then return false, "не удалось открыть на запись: " .. path end
    f.write(data)
    f.close()
    return true
end

-- Склеивание сегментов URL без двойных слэшей.
local function joinUrl(base, ...)
    local result = base:gsub("/+$", "")
    for _, part in ipairs({...}) do
        if part ~= nil and part ~= "" then
            local s = tostring(part):gsub("^/+", ""):gsub("/+$", "")
            result = result .. "/" .. s
        end
    end
    return result
end

-- ----------------------------------------------------------------------
-- Конфигурация
-- ----------------------------------------------------------------------

function M.getConfig()
    local cfgPath = paths.STORE_CFG
    if fs.exists(cfgPath) then
        local fn, err = loadfile(cfgPath, "t", {})
        if fn then
            local ok, tbl = pcall(fn)
            if ok and type(tbl) == "table" and type(tbl.url) == "string" then
                tbl.timeout = tonumber(tbl.timeout) or DEFAULT_CFG.timeout
                return tbl
            end
        end
        log.warn("store: не удалось прочитать " .. cfgPath .. ": " .. tostring(err))
    end
    -- Сохраняем дефолт
    local cfg = { url = DEFAULT_CFG.url, timeout = DEFAULT_CFG.timeout }
    M._saveConfig(cfg)
    return cfg
end

function M._saveConfig(cfg)
    ensureParent(paths.STORE_CFG)
    local body = ("return { url = %q, timeout = %d }\n"):format(
        cfg.url or DEFAULT_CFG.url,
        tonumber(cfg.timeout) or DEFAULT_CFG.timeout)
    local ok, err = writeFile(paths.STORE_CFG, body)
    if not ok then
        log.error("store: " .. tostring(err))
        return false, err
    end
    return true
end

function M.setUrl(url)
    if type(url) ~= "string" or url == "" then
        return false, "url должен быть непустой строкой"
    end
    local cfg = M.getConfig()
    cfg.url = url
    local ok, err = M._saveConfig(cfg)
    if not ok then return false, err end
    log.info("store: url обновлён на " .. url)
    -- Сбрасываем кэш индекса (раз url изменился)
    if fs.exists(INDEX_CACHE_PATH) then
        pcall(fs.delete, INDEX_CACHE_PATH)
    end
    return true
end

-- ----------------------------------------------------------------------
-- HTTP GET с обработкой ошибок
-- ----------------------------------------------------------------------

local function httpGet(url)
    if not http or not http.get then
        return nil, "http API недоступен"
    end
    local handle, err = http.get(url)
    if not handle then
        return nil, "HTTP ошибка: " .. tostring(err or "неизвестно") .. " (" .. url .. ")"
    end
    local code = 200
    if handle.getResponseCode then
        code = handle.getResponseCode() or 200
    end
    if code < 200 or code >= 300 then
        local body = handle.readAll() or ""
        handle.close()
        return nil, ("HTTP код %d для %s: %s"):format(code, url, body:sub(1, 120))
    end
    local body = handle.readAll()
    handle.close()
    if not body then
        return nil, "пустой ответ от " .. url
    end
    return body
end

-- ----------------------------------------------------------------------
-- Кэш индекса
-- ----------------------------------------------------------------------

local function cacheIsFresh()
    if not fs.exists(INDEX_CACHE_PATH) then return false end
    if not fs.attributes then return false end
    local ok, attr = pcall(fs.attributes, INDEX_CACHE_PATH)
    if not ok or type(attr) ~= "table" then return false end
    local mod = attr.modification or attr.modified
    if not mod then return false end
    -- modification в CC:Tweaked — миллисекунды с эпохи UTC
    local nowMs = os.epoch("utc")
    local ageSec = (nowMs - mod) / 1000
    return ageSec >= 0 and ageSec < INDEX_CACHE_TTL
end

local function readCachedIndex()
    local body = readFile(INDEX_CACHE_PATH)
    if not body then return nil end
    local ok, tbl = pcall(textutils.unserializeJSON, body)
    if ok and type(tbl) == "table" then return tbl end
    return nil
end

-- ----------------------------------------------------------------------
-- Fetch API
-- ----------------------------------------------------------------------

-- Внутренняя: получить распарсенный index.json (использует кэш по возможности).
local function fetchIndexRaw(useCache)
    if useCache and cacheIsFresh() then
        local cached = readCachedIndex()
        if cached then return cached end
    end
    local cfg = M.getConfig()
    local url = joinUrl(cfg.url, "index.json")
    local body, err = httpGet(url)
    if not body then return nil, err end
    local ok, parsed = pcall(textutils.unserializeJSON, body)
    if not ok or type(parsed) ~= "table" then
        return nil, "некорректный JSON в index.json"
    end
    ensureDir(paths.STORE_CACHE)
    pcall(writeFile, INDEX_CACHE_PATH, body)
    return parsed
end

-- Публичная: возвращает массив приложений из index.json.
function M.fetchIndex(opts)
    opts = opts or {}
    local useCache = opts.noCache ~= true
    local parsed, err = fetchIndexRaw(useCache)
    if not parsed then return nil, err end
    local apps = parsed.apps
    if type(apps) ~= "table" then
        return nil, "index.json не содержит поле apps"
    end
    return apps
end

function M.fetchManifest(appId)
    if type(appId) ~= "string" or appId == "" then
        return nil, "appId обязателен"
    end
    local cfg = M.getConfig()
    local url = joinUrl(cfg.url, "apps", appId, "manifest.lua")
    local body, err = httpGet(url)
    if not body then return nil, err end
    local fn, lerr = load(body, "manifest:" .. appId, "bt", {})
    if not fn then
        return nil, "ошибка загрузки manifest: " .. tostring(lerr)
    end
    local ok, result = pcall(fn)
    if not ok then
        return nil, "ошибка выполнения manifest: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "manifest не вернул таблицу"
    end
    local vok, verr = manifest.validate(result)
    if not vok then
        return nil, "валидация manifest: " .. tostring(verr)
    end
    return result
end

function M.fetchFile(appId, relPath)
    if type(appId) ~= "string" or appId == "" then
        return nil, "appId обязателен"
    end
    if type(relPath) ~= "string" or relPath == "" then
        return nil, "relPath обязателен"
    end
    local cfg = M.getConfig()
    local url = joinUrl(cfg.url, "apps", appId, "files", relPath)
    local body, err = httpGet(url)
    if not body then return nil, err end
    return body
end

function M.search(query)
    local apps, err = M.fetchIndex()
    if not apps then return nil, err end
    if not query or query == "" then
        return apps
    end
    local q = tostring(query):lower()
    local out = {}
    for _, app in ipairs(apps) do
        local id   = (app.id or ""):lower()
        local name = (app.name or ""):lower()
        local desc = (app.description or ""):lower()
        if id:find(q, 1, true)
            or name:find(q, 1, true)
            or desc:find(q, 1, true) then
            out[#out + 1] = app
        end
    end
    return out
end

return M
