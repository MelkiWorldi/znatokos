-- Виртуальная файловая система поверх fs.
-- Права (rwx для владельца / группы / остальных) хранятся в /znatokos/var/acl.db
local paths = znatokos.use("fs/paths")

local M = {}
local ACL_PATH = paths.VAR .. "/acl.db"

local current = { user = "root", uid = 0, gid = 0 }

local function ensureVar()
    if not fs.exists(paths.VAR) then fs.makeDir(paths.VAR) end
end

local function loadACL()
    ensureVar()
    if not fs.exists(ACL_PATH) then return {} end
    local f = fs.open(ACL_PATH, "r")
    local data = f.readAll(); f.close()
    local ok, t = pcall(textutils.unserialize, data)
    if ok and type(t) == "table" then return t end
    return {}
end

local function saveACL(t)
    ensureVar()
    local f = fs.open(ACL_PATH, "w")
    f.write(textutils.serialize(t)); f.close()
end

local acl = loadACL()

function M.setUser(u)
    current.user = u.user or "root"
    current.uid  = u.uid or 0
    current.gid  = u.gid or 0
end

function M.getUser() return current end

local function norm(p)
    if p:sub(1, 1) ~= "/" then p = "/" .. p end
    return fs.combine("/", p)
end

-- root разрешено всё. Иначе сверяем с ACL. Отсутствие записи = разрешено
-- всем, кроме записи в системные пути под /znatokos для не-root.
local function checkPerm(path, mode)
    if current.uid == 0 then return true end
    local entry = acl[norm(path)]
    if not entry then
        if mode == "r" or mode == "x" then return true end
        if path:sub(1, #paths.ROOT) == paths.ROOT then return false end
        return true
    end
    if entry.owner == current.user then
        return entry.mode:sub(1, 3):find(mode) ~= nil
    else
        return entry.mode:sub(-3):find(mode) ~= nil
    end
end

function M.chown(path, user)
    path = norm(path)
    acl[path] = acl[path] or { mode = "rwxr--" }
    acl[path].owner = user
    saveACL(acl)
end

function M.chmod(path, mode)
    path = norm(path)
    acl[path] = acl[path] or { owner = current.user }
    acl[path].mode = mode
    saveACL(acl)
end

function M.stat(path)
    path = norm(path)
    if not fs.exists(path) then return nil end
    return {
        path = path,
        isDir = fs.isDir(path),
        size = fs.getSize(path),
        acl = acl[path],
    }
end

function M.list(path)
    if not checkPerm(path, "r") then error("Отказано в доступе: " .. path) end
    return fs.list(path)
end

function M.exists(path)  return fs.exists(path) end
function M.isDir(path)   return fs.isDir(path) end
function M.getSize(path) return fs.getSize(path) end

function M.read(path)
    if not checkPerm(path, "r") then error("Отказано в доступе: " .. path) end
    local f = fs.open(path, "r"); if not f then return nil end
    local data = f.readAll(); f.close(); return data
end

function M.write(path, data)
    if not checkPerm(path, "w") then error("Отказано в доступе: " .. path) end
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w"); if not f then error("Не открыть: " .. path) end
    f.write(data); f.close()
    if not acl[norm(path)] then M.chown(path, current.user) end
end

function M.append(path, data)
    if not checkPerm(path, "w") then error("Отказано в доступе: " .. path) end
    local f = fs.open(path, "a"); if not f then error("Не открыть: " .. path) end
    f.write(data); f.close()
end

function M.delete(path)
    if not checkPerm(path, "w") then error("Отказано в доступе: " .. path) end
    fs.delete(path)
    acl[norm(path)] = nil
    saveACL(acl)
end

function M.move(src, dst)
    if not checkPerm(src, "w") then error("Отказано в доступе: " .. src) end
    fs.move(src, dst)
    acl[norm(dst)] = acl[norm(src)]; acl[norm(src)] = nil
    saveACL(acl)
end

function M.copy(src, dst)
    if not checkPerm(src, "r") then error("Отказано в доступе: " .. src) end
    fs.copy(src, dst)
end

function M.makeDir(path)
    local parent = fs.getDir(path)
    if parent == "" then parent = "/" end
    if not checkPerm(parent, "w") then error("Отказано в доступе: " .. path) end
    fs.makeDir(path)
end

return M
