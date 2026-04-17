-- Чтение удалённого репо. repo.json формата:
--   { packages = { name = { name, version, description, files = {{path,url}...}, deps } } }
-- Либо пустой, и тогда используется встроенный default.
local default = znatokos.use("pkg/repo_default")
local paths   = znatokos.use("fs/paths")

local M = {}

local CFG_URL = paths.ETC .. "/pkg_url.txt"

function M.getUrl()
    if not fs.exists(CFG_URL) then return nil end
    local f = fs.open(CFG_URL, "r"); local u = f.readAll(); f.close()
    return (u:gsub("%s+$", ""))
end

function M.setUrl(u)
    if not fs.exists(paths.ETC) then fs.makeDir(paths.ETC) end
    local f = fs.open(CFG_URL, "w"); f.write(u); f.close()
end

function M.loadRemote()
    local url = M.getUrl()
    if not url or not http then return nil end
    local h = http.get(url); if not h then return nil end
    local data = h.readAll(); h.close()
    local ok, obj = pcall(textutils.unserializeJSON, data)
    if not ok or type(obj) ~= "table" then return nil end
    return obj
end

function M.loadAll()
    local remote = M.loadRemote()
    local catalog = { packages = {} }
    for k, v in pairs(default.packages) do catalog.packages[k] = v end
    if remote and remote.packages then
        for k, v in pairs(remote.packages) do catalog.packages[k] = v end
    end
    return catalog
end

function M.fetchFile(file)
    if file.content then return file.content end
    if file.url and http then
        local h = http.get(file.url); if not h then return nil end
        local d = h.readAll(); h.close(); return d
    end
    return nil
end

return M
