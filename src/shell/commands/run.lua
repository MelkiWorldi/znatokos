-- run <файл.lua> [args...]
return function(args, ctx)
    if not args[2] then print("Использование: run <файл>"); return 1 end
    local path = args[2]
    if not path:find("%.lua$") then path = path .. ".lua" end
    if not path:find("^/") then path = fs.combine(ctx.cwd, path) end
    if not fs.exists(path) then print("Нет файла: " .. path); return 1 end
    local fn, err = loadfile(path, nil, _G)
    if not fn then print("Ошибка: " .. err); return 1 end
    local ok, e = pcall(fn, table.unpack(args, 3))
    if not ok then print("Сбой: " .. tostring(e)); return 1 end
    return 0
end
