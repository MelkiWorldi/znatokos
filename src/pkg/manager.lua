-- Пакетный менеджер ZnatokOS v0.3.0.
-- БД установок: /znatokos/var/pkg/installed.db (Lua-serialized).
-- Директория установленных приложений: /znatokos/apps/<id>/

local paths        = znatokos.use("fs/paths")
local log          = znatokos.use("kernel/log")
local manifestMod  = znatokos.use("pkg/manifest")
local sandbox      = znatokos.use("pkg/sandbox")
local store        = znatokos.use("pkg/store")

local M = {}

-- ----------------------------------------------------------------------
-- Вспомогательные функции
-- ----------------------------------------------------------------------

local function ensureDir(path)
    if not fs.exists(path) then fs.makeDir(path) end
end

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function appDir(appId)
    return paths.APPS_INSTALLED .. "/" .. appId
end

-- Сериализация manifest в строку Lua, возвращаемую из файла.
local function serializeManifest(m)
    return "return " .. textutils.serialize(m) .. "\n"
end

-- ----------------------------------------------------------------------
-- БД установленных
-- ----------------------------------------------------------------------

local function loadDB()
    if not fs.exists(paths.PKG_DB) then return {} end
    local f = fs.open(paths.PKG_DB, "r")
    if not f then return {} end
    local data = f.readAll(); f.close()
    local ok, tbl = pcall(textutils.unserialize, data)
    if ok and type(tbl) == "table" then return tbl end
    return {}
end

local function saveDB(db)
    ensureDir(paths.PKG_DIR)
    local f = fs.open(paths.PKG_DB, "w")
    if not f then
        log.error("pkg: не удалось сохранить БД установок")
        return false
    end
    f.write(textutils.serialize(db)); f.close()
    return true
end

-- ----------------------------------------------------------------------
-- Публичный API
-- ----------------------------------------------------------------------

function M.list()
    local db = loadDB()
    local out = {}
    for id, entry in pairs(db) do
        out[#out + 1] = {
            id = id,
            version = entry.version,
            manifest = entry.manifest,
            installedAt = entry.installedAt,
        }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function M.isInstalled(appId)
    local db = loadDB()
    return db[appId] ~= nil
end

function M.getInstalled(appId)
    local db = loadDB()
    return db[appId]
end

-- Внутренняя запись в БД.
local function recordInstalled(appId, manifest)
    local db = loadDB()
    db[appId] = {
        version     = manifest.version,
        installedAt = os.epoch("utc"),
        manifest    = manifest,
    }
    return saveDB(db)
end

-- Внутренняя: удаление физических файлов приложения.
local function removeAppFiles(appId)
    local dir = appDir(appId)
    if fs.exists(dir) then
        local ok, err = pcall(fs.delete, dir)
        if not ok then
            log.warn("pkg: не удалось удалить " .. dir .. ": " .. tostring(err))
            return false, err
        end
    end
    return true
end

-- Установить приложение. opts = { withDeps = true, force = false }
function M.install(appId, opts)
    opts = opts or {}
    if opts.withDeps == nil then opts.withDeps = true end

    if type(appId) ~= "string" or appId == "" then
        return false, "appId обязателен"
    end

    log.info("pkg: установка " .. appId)

    -- 1. Получить manifest
    local manifest, err = store.fetchManifest(appId)
    if not manifest then
        log.error("pkg: fetchManifest(" .. appId .. "): " .. tostring(err))
        return false, "manifest: " .. tostring(err)
    end
    if manifest.id ~= appId then
        return false, "id в manifest (" .. tostring(manifest.id) .. ") не совпадает с запрошенным (" .. appId .. ")"
    end

    -- 2. Валидация (fetchManifest уже валидирует, но для явности)
    local vok, verr = manifestMod.validate(manifest)
    if not vok then return false, "валидация: " .. tostring(verr) end

    -- 3. Проверка — уже установлено?
    if M.isInstalled(appId) and not opts.force then
        local existing = M.getInstalled(appId)
        if existing and existing.version == manifest.version then
            log.info("pkg: " .. appId .. " уже установлен (" .. manifest.version .. ")")
            return true
        end
        -- Разные версии — сначала чистим файлы
        log.info("pkg: переустановка " .. appId .. " (" .. tostring(existing and existing.version) .. " -> " .. manifest.version .. ")")
        removeAppFiles(appId)
    end

    -- 4. Создать директорию и скачать файлы
    local dir = appDir(appId)
    ensureParent(dir)
    ensureDir(dir)

    for _, relPath in ipairs(manifest.files) do
        local content, ferr = store.fetchFile(appId, relPath)
        if not content then
            log.error("pkg: не удалось получить " .. relPath .. ": " .. tostring(ferr))
            removeAppFiles(appId)
            return false, "файл " .. relPath .. ": " .. tostring(ferr)
        end
        local full = fs.combine(dir, relPath)
        ensureParent(full)
        local f = fs.open(full, "w")
        if not f then
            removeAppFiles(appId)
            return false, "не удалось открыть на запись: " .. full
        end
        f.write(content); f.close()
    end

    -- 5. Сохраняем manifest.lua локально
    local mPath = dir .. "/manifest.lua"
    local mf = fs.open(mPath, "w")
    if not mf then
        removeAppFiles(appId)
        return false, "не удалось записать manifest.lua"
    end
    mf.write(serializeManifest(manifest)); mf.close()

    -- 6. Записать в БД установок
    if not recordInstalled(appId, manifest) then
        return false, "не удалось обновить БД установок"
    end

    log.info("pkg: " .. appId .. " " .. manifest.version .. " установлен")

    -- 7. Зависимости
    if opts.withDeps and type(manifest.deps) == "table" then
        for depId, constraint in pairs(manifest.deps) do
            if M.isInstalled(depId) then
                local installed = M.getInstalled(depId)
                if installed and manifestMod.versionMatches(installed.version, constraint) then
                    log.info("pkg: зависимость " .. depId .. " уже установлена (" .. installed.version .. ")")
                else
                    log.info("pkg: обновляю зависимость " .. depId)
                    local dok, derr = M.install(depId, opts)
                    if not dok then
                        log.warn("pkg: сбой установки зависимости " .. depId .. ": " .. tostring(derr))
                        return false, "зависимость " .. depId .. ": " .. tostring(derr)
                    end
                end
            else
                log.info("pkg: устанавливаю зависимость " .. depId .. " (" .. tostring(constraint) .. ")")
                local dok, derr = M.install(depId, opts)
                if not dok then
                    return false, "зависимость " .. depId .. ": " .. tostring(derr)
                end
            end
        end
    end

    return true
end

function M.uninstall(appId)
    if type(appId) ~= "string" or appId == "" then
        return false, "appId обязателен"
    end
    local db = loadDB()
    if not db[appId] then
        return false, "не установлен: " .. appId
    end

    -- Удаляем файлы
    local ok, err = removeAppFiles(appId)
    if not ok then
        log.warn("pkg: uninstall файлов " .. appId .. ": " .. tostring(err))
    end

    -- Удаляем запись
    db[appId] = nil
    if not saveDB(db) then
        return false, "не удалось сохранить БД"
    end

    -- Очищаем права
    pcall(sandbox.permissionsClear, appId)

    log.info("pkg: " .. appId .. " удалён")
    return true
end

-- Обновить одно приложение; если в магазине версия новее — переустанавливает.
function M.update(appId)
    if type(appId) ~= "string" or appId == "" then
        return false, "appId обязателен"
    end
    local installed = M.getInstalled(appId)
    if not installed then
        return false, "не установлен: " .. appId
    end
    local remote, err = store.fetchManifest(appId)
    if not remote then return false, "manifest: " .. tostring(err) end
    local cmp = manifestMod.versionCompare(remote.version, installed.version)
    if cmp <= 0 then
        log.info("pkg: " .. appId .. " уже актуален (" .. installed.version .. ")")
        return true, "актуально"
    end
    log.info("pkg: обновление " .. appId .. " " .. installed.version .. " -> " .. remote.version)
    -- uninstall + install для чистоты
    local uok, uerr = M.uninstall(appId)
    if not uok then return false, "uninstall: " .. tostring(uerr) end
    return M.install(appId, { withDeps = true, force = true })
end

-- Проверить доступные обновления: array {{id, currentVersion, storeVersion}}.
function M.checkUpdates()
    local out = {}
    local index, err = store.fetchIndex()
    if not index then
        log.warn("pkg: checkUpdates fetchIndex: " .. tostring(err))
        return out, err
    end
    -- Строим быстрый lookup по id
    local byId = {}
    for _, app in ipairs(index) do
        if app.id and app.version then
            byId[app.id] = app.version
        end
    end
    local db = loadDB()
    for id, entry in pairs(db) do
        local storeVer = byId[id]
        if storeVer then
            local ok, cmp = pcall(manifestMod.versionCompare, storeVer, entry.version)
            if ok and cmp > 0 then
                out[#out + 1] = {
                    id = id,
                    currentVersion = entry.version,
                    storeVersion   = storeVer,
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Обновить все приложения с доступным апгрейдом.
function M.updateAll()
    local updates, err = M.checkUpdates()
    if err then return 0, { err } end
    local count, errors = 0, {}
    for _, u in ipairs(updates) do
        local ok, uerr = M.update(u.id)
        if ok then count = count + 1
        else errors[#errors + 1] = u.id .. ": " .. tostring(uerr) end
    end
    return count, errors
end

-- ----------------------------------------------------------------------
-- Заглушки совместимости со старым API (search/available/remove).
-- Делегируют новому функционалу и логируют warn.
-- ----------------------------------------------------------------------

function M.search(query)
    log.warn("pkg.manager.search устарел; используйте pkg/store.search")
    local res, err = store.search(query)
    if not res then return {}, err end
    return res
end

function M.available()
    log.warn("pkg.manager.available устарел; используйте pkg/store.fetchIndex")
    local apps, err = store.fetchIndex()
    if not apps then return {}, err end
    return apps
end

function M.remove(appId)
    log.warn("pkg.manager.remove устарел; используйте pkg.uninstall")
    return M.uninstall(appId)
end

return M
