-- pkg <list|installed|available|search|install|remove|uninstall|update|url>
-- Тонкая обёртка над новым store/manager API (сохраняется для совместимости).
local manager = znatokos.use("pkg/manager")
local store   = znatokos.use("pkg/store")

local function usage()
    print("Использование:")
    print("  pkg list                — установленные")
    print("  pkg installed           — то же, что list")
    print("  pkg available           — доступные в магазине")
    print("  pkg search <запрос>     — поиск")
    print("  pkg install <id>        — установить")
    print("  pkg remove|uninstall <id> — удалить")
    print("  pkg update [<id>]       — обновить")
    print("  pkg url [<url>]         — показать/задать URL магазина")
end

local function printInstalled()
    local list = manager.list()
    if #list == 0 then print("Ничего не установлено."); return end
    for _, e in ipairs(list) do
        local name = (e.manifest and e.manifest.name) or ""
        print(("  %-28s %-8s %s"):format(e.id, e.version or "?", name))
    end
end

local function printApps(apps)
    for _, app in ipairs(apps) do
        print(("  %-28s %-8s %s"):format(
            app.id or "?", app.version or "?",
            app.description or app.name or ""))
    end
end

return function(args)
    local sub = args[2] or "list"

    if sub == "list" or sub == "installed" then
        printInstalled()
        return 0

    elseif sub == "available" then
        local apps, err = store.fetchIndex()
        if not apps then print("Ошибка: " .. tostring(err)); return 1 end
        if #apps == 0 then print("Магазин пуст.") else printApps(apps) end
        return 0

    elseif sub == "search" then
        local res, err = store.search(args[3] or "")
        if not res then print("Ошибка: " .. tostring(err)); return 1 end
        if #res == 0 then print("Ничего не найдено.") else printApps(res) end
        return 0

    elseif sub == "install" then
        if not args[3] then print("pkg install <id>"); return 1 end
        print("Устанавливаем " .. args[3] .. "...")
        local ok, err = manager.install(args[3])
        if not ok then print("Сбой: " .. tostring(err)); return 1 end
        print("Готово.")
        return 0

    elseif sub == "remove" or sub == "uninstall" then
        if not args[3] then print("pkg remove <id>"); return 1 end
        local ok, err = manager.uninstall(args[3])
        if not ok then print("Сбой: " .. tostring(err)); return 1 end
        print("Удалено.")
        return 0

    elseif sub == "update" then
        if args[3] then
            local ok, err = manager.update(args[3])
            if not ok then print("Сбой: " .. tostring(err)); return 1 end
            print("Готово.")
            return 0
        end
        local n, errors = manager.updateAll()
        print(("Обновлено пакетов: %d"):format(n))
        for _, e in ipairs(errors) do print("  ! " .. e) end
        return (#errors == 0) and 0 or 1

    elseif sub == "url" then
        if args[3] then
            local ok, err = store.setUrl(args[3])
            if not ok then print("Сбой: " .. tostring(err)); return 1 end
            print("URL: " .. args[3])
        else
            local cfg = store.getConfig()
            print("URL: " .. tostring(cfg.url))
        end
        return 0

    elseif sub == "help" or sub == "-h" or sub == "--help" then
        usage(); return 0
    end

    print("Неизвестная команда: " .. tostring(sub))
    usage()
    return 1
end
