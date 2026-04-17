-- Передача файлов через rednet с ACK и чанками.
local net = znatokos.use("net/rednet")
local vfs = znatokos.use("fs/vfs")

local M = {}
local CHUNK = 2048

function M.send(to, srcPath, dstPath)
    if not vfs.exists(srcPath) then return false, "нет файла: " .. srcPath end
    if vfs.isDir(srcPath) then return false, "это каталог" end
    local data = vfs.read(srcPath) or ""
    local size = #data
    local chunks = math.max(1, math.ceil(size / CHUNK))
    net.send(to, "znatokos.ft.begin", { dst = dstPath, size = size, chunks = chunks, src = srcPath })
    local ack = net.receive("znatokos.ft.begin_ack", 5)
    if not ack then return false, "нет ответа получателя" end
    if not ack.payload.ok then return false, "отказано: " .. tostring(ack.payload.err) end
    for i = 1, chunks do
        local part = data:sub((i - 1) * CHUNK + 1, i * CHUNK)
        net.send(to, "znatokos.ft.chunk", { idx = i, data = part })
        local cack = net.receive("znatokos.ft.chunk_ack", 10)
        if not cack then return false, "нет ack #" .. i end
    end
    net.send(to, "znatokos.ft.end", {})
    return true
end

-- Приёмная петля. Возвращает таблицу с инфой о полученном файле.
function M.receive(timeout)
    local msg, from = net.receive("znatokos.ft.begin", timeout)
    if not msg then return nil, "timeout" end
    local dst = msg.payload.dst
    local chunks = msg.payload.chunks
    net.send(from, "znatokos.ft.begin_ack", { ok = true })
    local buf = {}
    for i = 1, chunks do
        local c = net.receive("znatokos.ft.chunk", 30)
        if not c then return nil, "обрыв на #" .. i end
        buf[c.payload.idx] = c.payload.data
        net.send(from, "znatokos.ft.chunk_ack", { idx = c.payload.idx })
    end
    net.receive("znatokos.ft.end", 5)
    local data = table.concat(buf)
    vfs.write(dst, data)
    return { src = msg.payload.src, dst = dst, size = #data, from = from }
end

return M
