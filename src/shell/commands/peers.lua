-- peers — CLI для discovery-слоя.
-- Использование:
--   peers [list]           список известных узлов
--   peers announce         послать свой hello
--   peers find <name>      показать конкретный узел

local disc_ok, disc = pcall(znatokos.use, "net/discovery")

-- Человекочитаемое "сколько назад".
local function agoStr(lastSeen)
    if not lastSeen then return "-" end
    local now = os.epoch("utc") / 1000
    local d = now - lastSeen
    if d < 0 then d = 0 end
    if d < 60 then
        return string.format("%d сек назад", math.floor(d))
    elseif d < 3600 then
        return string.format("%d мин назад", math.floor(d / 60))
    elseif d < 86400 then
        return string.format("%d ч назад", math.floor(d / 3600))
    else
        return string.format("%d дн назад", math.floor(d / 86400))
    end
end

local function truncate(s, n)
    s = tostring(s or "")
    if #s > n then return s:sub(1, n) end
    return s
end

local function printHeader()
    print(("%-14s %-16s %-12s %-8s %-5s %s"):format(
        "Имя", "ID", "Роль", "Связь", "Comp", "Посл. вид"))
end

local function printRow(p)
    local online = p.online
    print(("%-14s %-16s %-12s %-8s %-5s %s"):format(
        truncate(p.name, 14),
        truncate(p.id, 16),
        truncate(p.role or "-", 12),
        online and "online" or "offline",
        "#" .. tostring(p.computer_id or "?"),
        online and "-" or agoStr(p.last_seen)
    ))
end

local function cmdList()
    if not disc_ok or not disc then
        print("peers: discovery недоступен")
        return 1
    end
    local arr = disc.peers()
    if #arr == 0 then
        print("Известных узлов нет.")
        return 0
    end
    printHeader()
    for _, p in ipairs(arr) do printRow(p) end
    return 0
end

local function cmdAnnounce()
    if not disc_ok or not disc then
        print("peers: discovery недоступен")
        return 1
    end
    local ok, err = disc.announce()
    if ok then
        print("Hello отправлен.")
        return 0
    else
        print("Не удалось: " .. tostring(err or "?"))
        return 1
    end
end

local function cmdFind(name)
    if not name then
        print("Использование: peers find <name>")
        return 1
    end
    if not disc_ok or not disc then
        print("peers: discovery недоступен")
        return 1
    end
    local cid = disc.find(name)
    if not cid then
        print("Узел не найден: " .. name)
        return 1
    end
    for _, p in ipairs(disc.peers()) do
        if p.name == name then
            printHeader()
            printRow(p)
            return 0
        end
    end
    -- На всякий случай — нашли cid, но нет в списке (race condition).
    print(name .. " -> comp #" .. tostring(cid))
    return 0
end

return function(...)
    local args = { ... }
    local sub = args[1]
    if sub == nil or sub == "list" then
        return cmdList()
    elseif sub == "announce" then
        return cmdAnnounce()
    elseif sub == "find" then
        return cmdFind(args[2])
    else
        print("Использование: peers [list|announce|find <name>]")
        return 1
    end
end
