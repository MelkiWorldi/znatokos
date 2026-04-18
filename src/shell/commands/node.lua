-- node — управление идентичностью узла ЗнатокOS.
-- Использование:
--   node            показать текущую identity
--   node show       то же самое
--   node set-name <имя>
--   node set-role <role>
--   node reset      сгенерировать новый id (с подтверждением)
local node = znatokos.use("kernel/node")

local function fmtTime(epoch)
    if not epoch then return "?" end
    local ok, s = pcall(function()
        return os.date("%Y-%m-%d %H:%M:%S", math.floor(epoch / 1000))
    end)
    if ok and s then return s end
    return tostring(epoch)
end

local function showIdentity()
    local n = node.get()
    print("Идентичность узла:")
    print("  id      : " .. n.id)
    print("  name    : " .. n.name)
    local desc = node.VALID_ROLES[n.role] or "?"
    print("  role    : " .. n.role .. " (" .. desc .. ")")
    print("  created : " .. fmtTime(n.created_at))
end

local function usage()
    print("Использование:")
    print("  node [show]              показать identity")
    print("  node set-name <имя>      переименовать узел")
    print("  node set-role <role>     сменить роль")
    print("  node reset               сгенерировать новый id")
    print("Допустимые роли:")
    for k, v in pairs(node.VALID_ROLES) do
        print("  " .. k .. " — " .. v)
    end
end

return function(args)
    node.load()
    local sub = args[2]

    if sub == nil or sub == "show" then
        showIdentity()
        return 0
    end

    if sub == "set-name" then
        local name = args[3]
        if not name then
            print("Ошибка: укажите новое имя.")
            print("Пример: node set-name computer-3")
            return 1
        end
        local ok, err = node.setName(name)
        if not ok then
            print("Ошибка: " .. tostring(err))
            return 1
        end
        print("Имя узла: " .. name)
        return 0
    end

    if sub == "set-role" then
        local role = args[3]
        if not role then
            print("Ошибка: укажите роль.")
            print("Допустимые роли:")
            for k, v in pairs(node.VALID_ROLES) do
                print("  " .. k .. " — " .. v)
            end
            return 1
        end
        local ok, err = node.setRole(role)
        if not ok then
            print("Ошибка: " .. tostring(err))
            return 1
        end
        print("Роль узла: " .. role)
        return 0
    end

    if sub == "reset" then
        print("Будет сгенерирован новый id узла. Старый id будет потерян.")
        io.write("Продолжить? (yes/no): ")
        local answer = read()
        if answer ~= "yes" then
            print("Отменено.")
            return 1
        end
        local ok, newIdOrErr = node.reset()
        if not ok then
            print("Ошибка: " .. tostring(newIdOrErr))
            return 1
        end
        print("Новый id: " .. newIdOrErr)
        return 0
    end

    print("Неизвестная подкоманда: " .. tostring(sub))
    usage()
    return 1
end
