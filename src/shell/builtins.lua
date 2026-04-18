-- Реестр встроенных команд. Команда = файл в src/shell/commands/.
-- Каждая команда возвращает функцию (args, context) -> number (код возврата).
local paths = znatokos.use("fs/paths")

local M = {}

local CMDS = {
    "ls", "cd", "cat", "mkdir", "rm", "mv", "cp",
    "edit", "run", "lua", "help", "clear", "reboot", "shutdown",
    "ps", "kill", "top",
    "pkg", "net", "chat", "sendfile",
    "passwd", "useradd", "whoami", "logout",
    "monsetup",
}

local loaded = {}

function M.list() return CMDS end

function M.get(name)
    if loaded[name] ~= nil then return loaded[name] end
    local p = paths.COMMANDS .. "/" .. name .. ".lua"
    if not fs.exists(p) then
        loaded[name] = false
        return nil
    end
    local fn, err = loadfile(p, nil, _G)
    if not fn then error(("commands/%s.lua: %s"):format(name, err)) end
    local ok, res = pcall(fn)
    if not ok then error(("commands/%s.lua: %s"):format(name, res)) end
    loaded[name] = res
    return res
end

function M.has(name)
    if loaded[name] then return true end
    return fs.exists(paths.COMMANDS .. "/" .. name .. ".lua")
end

return M
