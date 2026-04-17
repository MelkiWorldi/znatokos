-- Пользователи ЗнатокOS.
-- Формат /znatokos/etc/passwd: Lua-таблица { [user] = {salt, hash, uid, gid, home, shell} }
local paths  = znatokos.use("fs/paths")
local sha    = znatokos.use("auth/sha256")

local M = {}

local function load()
    if not fs.exists(paths.PASSWD) then return {} end
    local f = fs.open(paths.PASSWD, "r")
    local data = f.readAll(); f.close()
    local ok, t = pcall(textutils.unserialize, data)
    if ok and type(t) == "table" then return t end
    return {}
end

local function save(db)
    local dir = fs.getDir(paths.PASSWD)
    if not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(paths.PASSWD, "w")
    f.write(textutils.serialize(db)); f.close()
end

function M.exists() return fs.exists(paths.PASSWD) end

function M.isEmpty()
    local db = load()
    return next(db) == nil
end

function M.list()
    local db = load()
    local arr = {}
    for name, rec in pairs(db) do
        arr[#arr + 1] = {
            user = name, uid = rec.uid, gid = rec.gid,
            home = rec.home, shell = rec.shell,
        }
    end
    table.sort(arr, function(a, b) return a.uid < b.uid end)
    return arr
end

function M.get(name)
    local db = load()
    local r = db[name]
    if not r then return nil end
    return {
        user = name, uid = r.uid, gid = r.gid,
        home = r.home, shell = r.shell,
    }
end

function M.create(name, password, opts)
    opts = opts or {}
    local db = load()
    if db[name] then return nil, "пользователь уже существует" end
    local uid
    if opts.uid then
        uid = opts.uid
    else
        uid = 1000
        for _, r in pairs(db) do if r.uid >= uid then uid = r.uid + 1 end end
        if next(db) == nil then uid = 0 end  -- первый = root
    end
    local salt = sha.makeSalt()
    db[name] = {
        salt = salt,
        hash = sha.saltedHash(password, salt),
        uid = uid,
        gid = opts.gid or uid,
        home = opts.home or ("/home/" .. name),
        shell = opts.shell or "/znatokos/src/shell/shell.lua",
    }
    save(db)
    if not fs.exists(db[name].home) then fs.makeDir(db[name].home) end
    return true
end

function M.verify(name, password)
    local db = load()
    local r = db[name]; if not r then return false end
    return sha.saltedHash(password, r.salt) == r.hash
end

function M.setPassword(name, password)
    local db = load()
    if not db[name] then return nil, "нет такого пользователя" end
    local salt = sha.makeSalt()
    db[name].salt = salt
    db[name].hash = sha.saltedHash(password, salt)
    save(db)
    return true
end

function M.delete(name)
    local db = load()
    if not db[name] then return nil, "нет такого пользователя" end
    db[name] = nil
    save(db)
    return true
end

return M
