-- rm <путь>
local vfs = znatokos.use("fs/vfs")
return function(args, ctx)
    if not args[2] then print("Использование: rm <путь>"); return 1 end
    local path = args[2]
    if not path:find("^/") then path = fs.combine(ctx.cwd, path) end
    if not vfs.exists(path) then print("Нет пути: " .. path); return 1 end
    vfs.delete(path); return 0
end
