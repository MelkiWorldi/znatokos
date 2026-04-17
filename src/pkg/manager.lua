-- Пакетный менеджер. БД установленных пакетов: /znatokos/var/pkg/installed.db
local repo  = znatokos.use("pkg/repo")
local paths = znatokos.use("fs/paths")
local vfs   = znatokos.use("fs/vfs")

local M = {}

local function loadDB()
    if not fs.exists(paths.PKG_DB) then return {} end
    local f = fs.open(paths.PKG_DB, "r"); local d = f.readAll(); f.close()
    local ok, t = pcall(textutils.unserialize, d)
    return ok and t or {}
end

local function saveDB(db)
    if not fs.exists(paths.PKG_DIR) then fs.makeDir(paths.PKG_DIR) end
    local f = fs.open(paths.PKG_DB, "w"); f.write(textutils.serialize(db)); f.close()
end

function M.list()
    return loadDB()
end

function M.available()
    return repo.loadAll().packages
end

function M.search(term)
    local out = {}
    for name, pkg in pairs(M.available()) do
        if not term or name:lower():find(term:lower(), 1, true)
           or (pkg.description and pkg.description:lower():find(term:lower(), 1, true)) then
            out[#out + 1] = pkg
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function M.install(name)
    local catalog = repo.loadAll()
    local pkg = catalog.packages[name]
    if not pkg then return false, "нет такого пакета: " .. name end
    -- Зависимости
    if pkg.deps then
        for _, d in ipairs(pkg.deps) do
            local ok, err = M.install(d)
            if not ok then return false, "зависимость " .. d .. ": " .. err end
        end
    end
    -- Файлы
    local installed = { files = {} }
    for _, file in ipairs(pkg.files or {}) do
        local data = repo.fetchFile(file)
        if not data then return false, "не удалось скачать " .. tostring(file.path) end
        vfs.write(file.path, data)
        installed.files[#installed.files + 1] = file.path
    end
    installed.name = pkg.name
    installed.version = pkg.version
    installed.installed_at = os.epoch("utc")
    local db = loadDB()
    db[pkg.name] = installed
    saveDB(db)
    return true
end

function M.remove(name)
    local db = loadDB()
    local rec = db[name]
    if not rec then return false, "не установлен" end
    for _, p in ipairs(rec.files) do
        if vfs.exists(p) then pcall(vfs.delete, p) end
    end
    db[name] = nil; saveDB(db)
    return true
end

function M.update()
    local count, errors = 0, {}
    local catalog = repo.loadAll().packages
    local db = loadDB()
    for name, rec in pairs(db) do
        local latest = catalog[name]
        if latest and latest.version ~= rec.version then
            local ok, err = M.install(name)
            if ok then count = count + 1
            else errors[#errors + 1] = name .. ": " .. err end
        end
    end
    return count, errors
end

return M
