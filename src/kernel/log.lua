-- Журнал системы. Пишет в /znatokos/var/log/system.log
local paths = znatokos.use("fs/paths")

local M = {}
local LOG_PATH = paths.LOG

local function ensure()
    local dir = fs.getDir(LOG_PATH)
    if not fs.exists(dir) then fs.makeDir(dir) end
end

local function stamp()
    return ("[%s] "):format(textutils.formatTime(os.time(), true))
end

local function writeLine(level, msg)
    ensure()
    local f = fs.open(LOG_PATH, "a")
    if not f then return end
    f.writeLine(stamp() .. level .. " " .. tostring(msg))
    f.close()
end

function M.info(msg)  writeLine("INFO ", msg) end
function M.warn(msg)  writeLine("WARN ", msg) end
function M.error(msg) writeLine("ERROR", msg) end
function M.debug(msg) writeLine("DEBUG", msg) end

function M.tail(n)
    n = n or 20
    if not fs.exists(LOG_PATH) then return {} end
    local f = fs.open(LOG_PATH, "r")
    local lines = {}
    while true do
        local l = f.readLine()
        if not l then break end
        lines[#lines + 1] = l
    end
    f.close()
    local start = math.max(1, #lines - n + 1)
    local out = {}
    for i = start, #lines do out[#out + 1] = lines[i] end
    return out
end

return M
