-- rpc — вызов удалённого метода через znatokos.rpc.
-- Использование:
--   rpc <target> <method> [<arg1> <arg2> ...]
--   rpc --list              список методов на этом компе
--   rpc --help              справка
local rpc = znatokos.use("net/rpc")

local function usage()
    print("Использование:")
    print("  rpc <target> <method> [arg1 arg2 ...]")
    print("  rpc --list              методы на этом компьютере")
    print("  rpc --help              эта справка")
    print("")
    print("target — id компьютера (число) или имя узла.")
    print("Примеры:")
    print("  rpc 3 ping")
    print("  rpc server-1 echo hello world")
    print("  rpc 5 info")
end

-- Форматирует значение результата: таблицы — через textutils.serialize
-- с заменой экранированных \n на реальные переносы для читабельности.
local function formatResult(v)
    if type(v) == "table" then
        local s = textutils.serialize(v)
        s = s:gsub("\\n", "\n")
        return s
    end
    return tostring(v)
end

return function(args)
    local first = args[2]
    if not first or first == "--help" or first == "-h" then
        usage(); return 0
    end

    if first == "--list" then
        local list = rpc.listMethods()
        if #list == 0 then
            print("Локальных методов нет.")
        else
            print("Локальные RPC-методы:")
            for _, m in ipairs(list) do print("  " .. m) end
        end
        return 0
    end

    local method = args[3]
    if not method then
        print("rpc: не указан метод.")
        usage(); return 1
    end

    -- target: число или строка.
    local target = tonumber(first) or first

    -- Остальные аргументы — массив строк.
    local callArgs = {}
    for i = 4, #args do callArgs[#callArgs + 1] = args[i] end

    local result, err = rpc.call(target, method, callArgs, 5)
    if err then
        print("rpc: ошибка — " .. tostring(err))
        return 1
    end
    print(formatResult(result))
    return 0
end
