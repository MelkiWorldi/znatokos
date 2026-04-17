-- cp <src> <dst>
local vfs = znatokos.use("fs/vfs")
return function(args, ctx)
    if not args[3] then print("Использование: cp <откуда> <куда>"); return 1 end
    local a, b = args[2], args[3]
    if not a:find("^/") then a = fs.combine(ctx.cwd, a) end
    if not b:find("^/") then b = fs.combine(ctx.cwd, b) end
    vfs.copy(a, b); return 0
end
