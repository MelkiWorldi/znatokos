-- ls [путь]
local vfs   = znatokos.use("fs/vfs")
local theme = znatokos.use("ui/theme")
return function(args, ctx)
    local path = args[2] or ctx.cwd
    if not path:find("^/") then path = fs.combine(ctx.cwd, path) end
    if not vfs.exists(path) then
        print("Нет такого пути: " .. path); return 1
    end
    if not vfs.isDir(path) then
        print(path); return 0
    end
    local list = vfs.list(path)
    table.sort(list)
    local th = theme.get()
    for _, name in ipairs(list) do
        local full = fs.combine(path, name)
        if vfs.isDir(full) then
            term.setTextColor(colors.lightBlue); io.write(name .. "/")
        else
            term.setTextColor(th.fg); io.write(name)
        end
        io.write("  ")
    end
    term.setTextColor(th.fg); print("")
    return 0
end
