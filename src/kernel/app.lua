-- kernel/app — единая точка запуска приложений ЗнатокOS.
--
-- Два режима:
--   * runLegacy — приложения старого образца: файл возвращает function(user).
--                 Без манифеста и sandbox; все права дефолтные. Переходный период.
--   * run      — приложения нового образца с manifest.lua и sandbox'ом.
--
-- Также listInstalled / isInstalled — для desktop и shell.
local log       = znatokos.use("kernel/log")
local wm        = znatokos.use("kernel/window")
local sched     = znatokos.use("kernel/scheduler")
local paths     = znatokos.use("fs/paths")
local manifest  = znatokos.use("pkg/manifest")
local dialog    = znatokos.use("ui/dialog")

local M = {}

-- sandbox загружается лениво: он может быть ещё не готов в iter где app.lua
-- уже нужен desktop'у. Любая ошибка загрузки -> M.run недоступен.
local function getSandbox()
    local ok, mod = pcall(znatokos.use, "pkg/sandbox")
    if not ok then return nil, tostring(mod) end
    return mod, nil
end

--------------------------------------------------------------
-- runLegacy: запуск старого-стиля app (файл возвращает function(user))
--------------------------------------------------------------
function M.runLegacy(appFilePath, opts)
    opts = opts or {}
    if type(appFilePath) ~= "string" or #appFilePath == 0 then
        return nil, "путь не задан"
    end
    if not fs.exists(appFilePath) then
        log.warn("app.runLegacy: файл не найден: " .. appFilePath)
        return nil, "файл не найден: " .. appFilePath
    end

    -- Подгружаем файл. Он должен вернуть function(user).
    local chunk, loadErr = loadfile(appFilePath, nil, _G)
    if not chunk then
        log.error("app.runLegacy: load error: " .. tostring(loadErr))
        return nil, "ошибка загрузки: " .. tostring(loadErr)
    end
    local ok, appFn = pcall(chunk)
    if not ok then
        log.error("app.runLegacy: runtime error: " .. tostring(appFn))
        return nil, "ошибка выполнения: " .. tostring(appFn)
    end
    if type(appFn) ~= "function" then
        return nil, "app должен возвращать function(user)"
    end

    local title = opts.title or fs.getName(appFilePath) or "app"
    local winEntry = wm.create({
        title = title, owner = opts.user or 0,
        w = opts.width, h = opts.height,
    })
    wm.focus(winEntry.id)

    local user = opts.user
    local pid, spawnErr = sched.spawn({
        name   = title,
        owner  = (type(user) == "table" and user.name) or tostring(user or "root"),
        window = winEntry,
        fn = function()
            local okr, err = pcall(appFn, user)
            if not okr then
                log.error(("app '%s' crash: %s"):format(title, tostring(err)))
                -- Показать ошибку в окне и дождаться клавиши
                pcall(function()
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.red)
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("[" .. title .. "] ошибка:")
                    term.setTextColor(colors.white)
                    print(tostring(err))
                    print("")
                    print("Нажмите любую клавишу...")
                    os.pullEvent("key")
                end)
            end
        end,
    })
    if not pid then
        wm.destroy(winEntry.id)
        log.error("app.runLegacy: spawn failed: " .. tostring(spawnErr))
        return nil, spawnErr or "spawn failed"
    end
    log.info(("app.runLegacy: %s pid=%d"):format(title, pid))
    return pid
end

--------------------------------------------------------------
-- run: запуск нового-стиля app через manifest + sandbox
--------------------------------------------------------------
function M.run(appId, user)
    if type(appId) ~= "string" or #appId == 0 then
        return nil, "appId не задан"
    end
    local appDir = paths.APPS_INSTALLED .. "/" .. appId
    local manifestPath = appDir .. "/manifest.lua"

    if not fs.exists(manifestPath) then
        local err = "manifest не найден: " .. manifestPath
        log.error("app.run: " .. err)
        pcall(dialog.message, "Ошибка запуска", err)
        return nil, err
    end

    -- Загрузка + валидация манифеста
    local m, loadErr = manifest.load(manifestPath)
    if not m then
        log.error("app.run: " .. tostring(loadErr))
        pcall(dialog.message, "Ошибка манифеста", tostring(loadErr))
        return nil, loadErr
    end
    local validOk, validErr = manifest.validate(m)
    if not validOk then
        log.error("app.run: validate: " .. tostring(validErr))
        pcall(dialog.message, "Манифест некорректен", tostring(validErr))
        return nil, validErr
    end

    -- Sandbox
    local sandbox, sbErr = getSandbox()
    if not sandbox then
        local err = "pkg/sandbox недоступен: " .. tostring(sbErr)
        log.error("app.run: " .. err)
        pcall(dialog.message, "Ошибка запуска", err)
        return nil, err
    end

    local requestedCaps = m.capabilities or {}

    -- Определить, какие capability-id ещё не решены пользователем.
    local unknown = {}
    do
        local ok, list = pcall(sandbox.permissionsUnknown, appId, requestedCaps)
        if ok and type(list) == "table" then unknown = list end
    end

    if #unknown > 0 then
        local answers = dialog.permissionPrompt(m, unknown)
        if answers == nil then
            log.info(("app.run: user cancelled permissions for %s"):format(appId))
            return nil, "user cancelled"
        end
        for _, cid in ipairs(unknown) do
            local allow = answers[cid] and true or false
            pcall(sandbox.permissionsGrant, appId, cid, allow)
        end
    end

    -- Финальный набор разрешённых capabilities.
    local granted = {}
    do
        local ok, perms = pcall(sandbox.permissionsGet, appId)
        if ok and type(perms) == "table" then
            for _, cid in ipairs(requestedCaps) do
                if perms[cid] then granted[#granted + 1] = cid end
            end
        end
    end

    -- Missing (те что запрошены но не даны) — приложение запускается с тем что есть;
    -- sandbox сам будет решать, фатально это или нет.
    local missing = {}
    do
        local ok, list = pcall(sandbox.permissionsMissing, appId, requestedCaps)
        if ok and type(list) == "table" then missing = list end
    end
    if #missing > 0 then
        log.warn(("app.run: %s missing caps: %s")
            :format(appId, table.concat(missing, ",")))
    end

    -- Окно
    local winEntry = wm.create({
        title = m.name, owner = (type(user) == "table" and user.name) or tostring(user or "root"),
    })
    wm.focus(winEntry.id)

    -- Загрузка app через sandbox
    local okLoad, fnOrErr = pcall(sandbox.loadApp, m, {
        appId  = appId,
        user   = user,
        caps   = granted,
        appDir = appDir,
        window = winEntry,
    })
    if not okLoad or type(fnOrErr) ~= "function" then
        wm.destroy(winEntry.id)
        local err = (not okLoad) and tostring(fnOrErr) or "sandbox.loadApp вернул не функцию"
        log.error("app.run: loadApp: " .. err)
        pcall(dialog.message, "Ошибка запуска", err)
        return nil, err
    end
    local appFn = fnOrErr

    local pid, spawnErr = sched.spawn({
        name   = m.name,
        owner  = (type(user) == "table" and user.name) or tostring(user or "root"),
        window = winEntry,
        fn = function()
            local okr, err = pcall(appFn)
            if not okr then
                log.error(("app '%s' crash: %s"):format(m.name, tostring(err)))
                pcall(function()
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.red)
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("[" .. m.name .. "] ошибка:")
                    term.setTextColor(colors.white)
                    print(tostring(err))
                    print("")
                    print("Нажмите любую клавишу...")
                    os.pullEvent("key")
                end)
            end
        end,
    })
    if not pid then
        wm.destroy(winEntry.id)
        log.error("app.run: spawn failed: " .. tostring(spawnErr))
        return nil, spawnErr or "spawn failed"
    end

    log.info(("app.run: %s (%s) pid=%d"):format(m.name, appId, pid))
    return pid
end

--------------------------------------------------------------
-- listInstalled / isInstalled
--------------------------------------------------------------
function M.listInstalled()
    local out = {}
    if not fs.exists(paths.APPS_INSTALLED) or not fs.isDir(paths.APPS_INSTALLED) then return out end
    local ok, entries = pcall(fs.list, paths.APPS_INSTALLED)
    if not ok or type(entries) ~= "table" then return out end
    for _, name in ipairs(entries) do
        local dir = paths.APPS_INSTALLED .. "/" .. name
        if fs.isDir(dir) then
            local mPath = dir .. "/manifest.lua"
            if fs.exists(mPath) then
                local m, err = manifest.load(mPath)
                if m then
                    local validOk = select(1, manifest.validate(m))
                    if validOk then
                        out[#out + 1] = { id = m.id or name, manifest = m }
                    else
                        log.warn(("listInstalled: %s invalid manifest"):format(name))
                    end
                else
                    log.warn(("listInstalled: %s load err: %s"):format(name, tostring(err)))
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.id or "") < (b.id or "") end)
    return out
end

function M.isInstalled(appId)
    if type(appId) ~= "string" or #appId == 0 then return false end
    local mPath = paths.APPS_INSTALLED .. "/" .. appId .. "/manifest.lua"
    if not fs.exists(mPath) then return false end
    local m = manifest.load(mPath)
    if not m then return false end
    return select(1, manifest.validate(m)) == true
end

return M
