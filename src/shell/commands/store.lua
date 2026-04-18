-- store <list|installed|search|info|install|uninstall|update|url>
-- CLI для магазина приложений ZnatokOS.
local store   = znatokos.use("pkg/store")
local manager = znatokos.use("pkg/manager")

local function usage()
    print("Использование:")
    print("  store list              — список из магазина")
    print("  store installed         — установленные")
    print("  store search <запрос>   — поиск")
    print("  store info <id>         — детали приложения")
    print("  store install <id>      — установить")
    print("  store uninstall <id>    — удалить")
    print("  store update [<id>]     — обновить (всё или одно)")
    print("  store url [<url>]       — показать/задать URL магазина")
end

local function printAppRow(app)
    print(("  %-28s %-8s %s"):format(
        app.id or "?",
        app.version or "?",
        app.name or ""))
end

return function(args)
    local sub = args[2]
    if not sub or sub == "help" or sub == "-h" or sub == "--help" then
        usage(); return 0
    end

    if sub == "list" then
        local apps, err = store.fetchIndex()
        if not apps then
            print("Ошибка: " .. tostring(err)); return 1
        end
        if #apps == 0 then print("Магазин пуст."); return 0 end
        print(("Доступно приложений: %d"):format(#apps))
        for _, app in ipairs(apps) do printAppRow(app) end
        return 0

    elseif sub == "installed" then
        local list = manager.list()
        if #list == 0 then print("Ничего не установлено."); return 0 end
        for _, e in ipairs(list) do
            local name = (e.manifest and e.manifest.name) or ""
            print(("  %-28s %-8s %s"):format(e.id, e.version or "?", name))
        end
        return 0

    elseif sub == "search" then
        local q = args[3]
        if not q then print("store search <запрос>"); return 1 end
        local res, err = store.search(q)
        if not res then print("Ошибка: " .. tostring(err)); return 1 end
        if #res == 0 then print("Ничего не найдено."); return 0 end
        for _, app in ipairs(res) do printAppRow(app) end
        return 0

    elseif sub == "info" then
        local id = args[3]
        if not id then print("store info <id>"); return 1 end
        local m, err = store.fetchManifest(id)
        if not m then print("Ошибка: " .. tostring(err)); return 1 end
        print("ID:         " .. tostring(m.id))
        print("Имя:        " .. tostring(m.name))
        print("Версия:     " .. tostring(m.version))
        if m.author then      print("Автор:      " .. m.author) end
        if m.description then print("Описание:   " .. m.description) end
        print("Entry:      " .. tostring(m.entry))
        print(("Файлов:     %d"):format(#(m.files or {})))
        if type(m.capabilities) == "table" and #m.capabilities > 0 then
            print("Права:      " .. table.concat(m.capabilities, ", "))
        end
        if type(m.deps) == "table" then
            local deps = {}
            for d, c in pairs(m.deps) do deps[#deps + 1] = d .. " " .. c end
            if #deps > 0 then print("Зависимости: " .. table.concat(deps, ", ")) end
        end
        if manager.isInstalled(id) then
            local e = manager.getInstalled(id)
            print(("Установлено: %s"):format(e.version or "?"))
        else
            print("Установлено: нет")
        end
        return 0

    elseif sub == "install" then
        local id = args[3]
        if not id then print("store install <id>"); return 1 end
        print("Устанавливаем " .. id .. "...")
        local ok, err = manager.install(id)
        if not ok then print("Сбой: " .. tostring(err)); return 1 end
        print("Готово.")
        return 0

    elseif sub == "uninstall" or sub == "remove" then
        local id = args[3]
        if not id then print("store uninstall <id>"); return 1 end
        local ok, err = manager.uninstall(id)
        if not ok then print("Сбой: " .. tostring(err)); return 1 end
        print("Удалено: " .. id)
        return 0

    elseif sub == "update" then
        local id = args[3]
        if id then
            print("Обновление " .. id .. "...")
            local ok, err = manager.update(id)
            if not ok then print("Сбой: " .. tostring(err)); return 1 end
            print("Готово.")
            return 0
        end
        local updates, err = manager.checkUpdates()
        if err and #updates == 0 then
            print("Ошибка: " .. tostring(err)); return 1
        end
        if #updates == 0 then
            print("Все приложения актуальны."); return 0
        end
        print(("Обновлений: %d"):format(#updates))
        for _, u in ipairs(updates) do
            print(("  %s %s -> %s"):format(u.id, u.currentVersion, u.storeVersion))
        end
        local n, errors = manager.updateAll()
        print(("Обновлено: %d"):format(n))
        for _, e in ipairs(errors) do print("  ! " .. e) end
        return (#errors == 0) and 0 or 1

    elseif sub == "url" then
        if args[3] then
            local ok, err = store.setUrl(args[3])
            if not ok then print("Сбой: " .. tostring(err)); return 1 end
            print("URL: " .. args[3])
        else
            local cfg = store.getConfig()
            print("URL:     " .. tostring(cfg.url))
            print("Timeout: " .. tostring(cfg.timeout))
        end
        return 0
    end

    print("Неизвестная команда: " .. tostring(sub))
    usage()
    return 1
end
