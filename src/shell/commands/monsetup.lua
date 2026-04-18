-- monsetup <cols> <rows>
-- Настраивает тайлинг нескольких отдельных мониторов.
-- 1. Находит все мониторы, рисует на каждом крупную цифру-идентификатор.
-- 2. Спрашивает у пользователя, какие ID видны в каком порядке (left-to-right, top-to-bottom).
-- 3. Сохраняет /znatokos/etc/display.cfg.
local display = znatokos.use("kernel/display")
local paths   = znatokos.use("fs/paths")
local theme   = znatokos.use("ui/theme")

-- крупные цифры 5×5 для подписи мониторов
local BIG = {
    ["0"]={"#####","#   #","#   #","#   #","#####"},
    ["1"]={"  #  "," ##  ","  #  ","  #  ","#####"},
    ["2"]={"#####","    #","#####","#    ","#####"},
    ["3"]={"#####","    #","#####","    #","#####"},
    ["4"]={"#   #","#   #","#####","    #","    #"},
    ["5"]={"#####","#    ","#####","    #","#####"},
    ["6"]={"#####","#    ","#####","#   #","#####"},
    ["7"]={"#####","    #","    #","    #","    #"},
    ["8"]={"#####","#   #","#####","#   #","#####"},
    ["9"]={"#####","#   #","#####","    #","#####"},
}

local function paintNumberOn(mon, str)
    pcall(mon.setTextScale, 1)
    mon.setBackgroundColor(colors.black); mon.clear()
    mon.setTextColor(colors.lime)
    local w, h = mon.getSize()
    local startY = math.max(1, math.floor((h - 5) / 2))
    local lines = { "", "", "", "", "" }
    for i = 1, #str do
        local g = BIG[str:sub(i, i)] or {"  ?  ","  ?  ","  ?  ","  ?  ","  ?  "}
        for r = 1, 5 do lines[r] = lines[r] .. g[r] .. " " end
    end
    for r = 1, 5 do
        local lx = math.max(1, math.floor((w - #lines[r]) / 2) + 1)
        mon.setCursorPos(lx, startY + r - 1)
        mon.write(lines[r])
    end
end

local function clearMonitor(mon)
    pcall(mon.setTextScale, 0.5)
    mon.setBackgroundColor(colors.black); mon.clear()
end

return function(args)
    local cols = tonumber(args[2])
    local rows = tonumber(args[3])
    if not cols or not rows then
        print("Использование: monsetup <cols> <rows>")
        print("Пример: monsetup 4 3  — стенка 4 в ширину × 3 в высоту")
        return 1
    end
    local names = display.listAllMonitors()
    local needed = cols * rows
    if #names < needed then
        print(("Нужно %d мониторов, найдено %d"):format(needed, #names))
        return 1
    end
    print(("Найдено мониторов: %d"):format(#names))
    for i, n in ipairs(names) do
        local mon = peripheral.wrap(n)
        if mon then paintNumberOn(mon, tostring(i)) end
        print(("  [%d] %s"):format(i, n))
    end
    print("")
    print(("Введи %d номеров через запятую,"):format(needed))
    print("в порядке слева направо, сверху вниз.")
    print("Пример для 4x3: 1,2,3,4,5,6,7,8,9,10,11,12")
    io.write("> ")
    local line = read()
    local order = {}
    for part in line:gmatch("[^,%s]+") do
        local n = tonumber(part)
        if not n or not names[n] then
            print("Неверный номер: " .. tostring(part))
            for _, nm in ipairs(names) do pcall(clearMonitor, peripheral.wrap(nm)) end
            return 1
        end
        order[#order + 1] = names[n]
    end
    if #order ~= needed then
        print(("Ожидалось %d номеров, получено %d"):format(needed, #order))
        for _, nm in ipairs(names) do pcall(clearMonitor, peripheral.wrap(nm)) end
        return 1
    end
    local cfg = {
        tile = { cols = cols, rows = rows },
        monitors = order,
    }
    display.saveConfig(cfg)
    print("Сохранено: " .. paths.ETC .. "/display.cfg")
    print("Сделай reboot чтобы применить.")
    for _, nm in ipairs(names) do pcall(clearMonitor, peripheral.wrap(nm)) end
    return 0
end
