-- mkdir <имя>
local vfs = znatokos.use("fs/vfs")
return function(args, ctx)
    if not args[2] then print("Использование: mkdir <имя>"); return 1 end
    local path = args[2]
    if not path:find("^/") then path = fs.combine(ctx.cwd, path) end
    if vfs.exists(path) then print("Уже существует: " .. path); return 1 end
    vfs.makeDir(path); return 0
end
