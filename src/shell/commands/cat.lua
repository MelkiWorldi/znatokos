-- cat <файл>
local vfs = znatokos.use("fs/vfs")
return function(args, ctx)
    if not args[2] then print("Использование: cat <файл>"); return 1 end
    local path = args[2]
    if not path:find("^/") then path = fs.combine(ctx.cwd, path) end
    if not vfs.exists(path) or vfs.isDir(path) then
        print("Нет такого файла: " .. path); return 1
    end
    local data = vfs.read(path) or ""
    print(data)
    return 0
end
