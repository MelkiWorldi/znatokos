-- pkg <list|available|search|install|remove|update|url>
local pkg  = znatokos.use("pkg/manager")
local repo = znatokos.use("pkg/repo")
return function(args)
    local sub = args[2] or "list"
    if sub == "list" then
        local db = pkg.list()
        if next(db) == nil then print("Ничего не установлено.") end
        for name, r in pairs(db) do print(("  %s  %s"):format(name, r.version or "?")) end
    elseif sub == "available" then
        for _, p in ipairs(pkg.search(nil)) do
            print(("  %-12s %-8s %s"):format(p.name, p.version or "?", p.description or ""))
        end
    elseif sub == "search" then
        for _, p in ipairs(pkg.search(args[3] or "")) do
            print(("  %-12s %-8s %s"):format(p.name, p.version or "?", p.description or ""))
        end
    elseif sub == "install" then
        if not args[3] then print("pkg install <имя>"); return 1 end
        print("Устанавливаем " .. args[3] .. "...")
        local ok, err = pkg.install(args[3])
        if not ok then print("Сбой: " .. err); return 1 end
        print("Готово.")
    elseif sub == "remove" then
        if not args[3] then print("pkg remove <имя>"); return 1 end
        local ok, err = pkg.remove(args[3])
        if not ok then print("Сбой: " .. err); return 1 end
        print("Удалено.")
    elseif sub == "update" then
        local n, errs = pkg.update()
        print(("Обновлено пакетов: %d"):format(n))
        for _, e in ipairs(errs) do print("  !" .. e) end
    elseif sub == "url" then
        if args[3] then repo.setUrl(args[3]); print("Репо: " .. args[3])
        else print(repo.getUrl() or "(встроенный каталог)") end
    else
        print("pkg [list|available|search|install|remove|update|url]")
    end
    return 0
end
