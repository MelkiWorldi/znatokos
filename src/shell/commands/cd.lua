-- cd <путь>
local vfs = znatokos.use("fs/vfs")
return function(args, ctx)
    local target = args[2] or "/"
    if not target:find("^/") then target = fs.combine(ctx.cwd, target) end
    target = fs.combine("/", target)
    if not vfs.exists(target) then print("Нет каталога: " .. target); return 1 end
    if not vfs.isDir(target) then print("Не каталог: " .. target); return 1 end
    ctx.cwd = target
    return 0
end
