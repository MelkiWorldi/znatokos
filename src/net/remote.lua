-- Удалённый шелл через rednet. Запросы подписываются общим pre-shared key.
-- Команда запускается на хосте, результат возвращается.
local net   = znatokos.use("net/rednet")
local sha   = znatokos.use("auth/sha256")
local paths = znatokos.use("fs/paths")

local M = {}

local function loadKey()
    local p = paths.ETC .. "/remote.key"
    if not fs.exists(p) then return nil end
    local f = fs.open(p, "r"); local k = f.readAll(); f.close(); return k
end

local function sign(msg, key)
    return sha.hash((key or "") .. textutils.serialize(msg))
end

function M.runHost()
    local key = loadKey()
    if not key then print("Нет /znatokos/etc/remote.key — remote shell отключён."); return end
    while true do
        local msg, from = net.receive("znatokos.remote.cmd")
        if msg and msg.payload and sign(msg.payload.body, key) == msg.payload.sig then
            local cmd = msg.payload.body.cmd
            local out = {}
            local oldPrint = print
            _G.print = function(...)
                local parts = { ... }
                for i, v in ipairs(parts) do parts[i] = tostring(v) end
                out[#out + 1] = table.concat(parts, "\t")
            end
            local ok, err = pcall(function() shell.run(cmd) end)
            _G.print = oldPrint
            local body = { out = table.concat(out, "\n"), ok = ok, err = tostring(err) }
            net.send(from, "znatokos.remote.resp", { body = body, sig = sign(body, key) })
        end
    end
end

function M.sendCmd(to, cmd, timeout)
    local key = loadKey()
    if not key then return nil, "нет ключа" end
    local body = { cmd = cmd }
    net.send(to, "znatokos.remote.cmd", { body = body, sig = sign(body, key) })
    local resp = net.receive("znatokos.remote.resp", timeout or 10)
    if not resp then return nil, "timeout" end
    if sign(resp.payload.body, key) ~= resp.payload.sig then return nil, "bad sig" end
    return resp.payload.body
end

return M
