-- sendfile <файл> <computer_id> [удалённый_путь]
local ft  = znatokos.use("net/filetransfer")
local net = znatokos.use("net/rednet")
return function(args, ctx)
    if not args[3] then print("Использование: sendfile <файл> <id> [путь]"); return 1 end
    local src = args[2]; if not src:find("^/") then src = fs.combine(ctx.cwd, src) end
    local id = tonumber(args[3])
    local dst = args[4] or ("/" .. fs.getName(src))
    if not net.ensureOpen() then print("Нет модема."); return 1 end
    print(("Отправка %s → #%d:%s"):format(src, id, dst))
    local ok, err = ft.send(id, src, dst)
    if not ok then print("Сбой: " .. tostring(err)); return 1 end
    print("Готово.")
    return 0
end
