-- help [команда]
local builtins = znatokos.use("shell/builtins")

local DESC = {
    ls = "список файлов в каталоге",
    cd = "сменить текущий каталог",
    cat = "вывести содержимое файла",
    mkdir = "создать каталог",
    rm = "удалить файл или каталог",
    mv = "переместить/переименовать",
    cp = "скопировать файл",
    edit = "редактор с подсветкой Lua",
    run = "запустить Lua-скрипт",
    ["lua"] = "интерактивный Lua REPL",
    clear = "очистить экран",
    reboot = "перезагрузка компьютера",
    shutdown = "выключение компьютера",
    ps = "список задач",
    kill = "завершить задачу по pid",
    top = "монитор задач в реальном времени",
    pkg = "пакетный менеджер (install/list/remove/update)",
    net = "информация о сети",
    chat = "сетевой чат через rednet",
    sendfile = "отправить файл на другой компьютер",
    passwd = "сменить пароль пользователя",
    useradd = "создать пользователя",
    whoami = "текущий пользователь",
    logout = "выйти из текущего сеанса",
    help = "справка по командам",
    alias = "создать или вывести alias",
    exit = "выйти из шелла",
}

return function(args)
    if args[2] then
        local d = DESC[args[2]]
        if d then print(args[2] .. " — " .. d)
        else print("Нет справки для: " .. args[2]) end
        return 0
    end
    print("Доступные команды:")
    local names = {}
    for k in pairs(DESC) do names[#names + 1] = k end
    table.sort(names)
    for _, n in ipairs(names) do
        print(("  %-10s %s"):format(n, DESC[n]))
    end
    return 0
end
