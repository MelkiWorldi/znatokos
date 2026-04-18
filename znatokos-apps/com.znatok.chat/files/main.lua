-- Чат ZnatokOS. Автономное приложение: общается по rednet напрямую,
-- без обращения к модулям ОС. Два параллельных цикла: приём и отправка.

-- Получаем имя пользователя из контекста приложения либо через VFS.
local user = (znatokos.app and znatokos.app.user)
         or (znatokos.use("fs/vfs").getUser() or { user = "guest" })
local nickname = user.user or "guest"

-- Локальный аналог net.ensureOpen: проходим по всем сторонам и открываем модемы.
local opened = false
local function ensureOpen()
    if opened then return true end
    local any = false
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then rednet.open(side) end
            any = true
        end
    end
    opened = any
    return any
end

local function myId() return os.getComputerID() end

local function myLabel()
    return os.getComputerLabel() or ("comp-" .. os.getComputerID())
end

-- Отправка broadcast-фрейма в протоколе ZnatokOS.
local function broadcast(proto, payload)
    if not ensureOpen() then return false, "нет модема" end
    local frame = {
        proto = proto,
        from = myId(),
        to = "*",
        payload = payload,
        nonce = os.epoch("utc") .. "." .. math.random(1, 1e6),
    }
    rednet.broadcast(frame, "znatokos")
    return true
end

-- Приём фрейма с фильтром по протоколу.
local function receive(filter)
    if not ensureOpen() then return nil end
    while true do
        local id, msg = rednet.receive("znatokos")
        if not id then return nil end
        if type(msg) == "table" and (not filter or msg.proto == filter) then
            return msg, id
        end
    end
end

-- Экран ошибки «Нет модема» с ожиданием клавиши.
if not ensureOpen() then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("Нет модема.")
    term.setTextColor(colors.white)
    print("")
    print("Присоедините wireless или ender")
    print("modem к компьютеру (любая сторона)")
    print("и перезапустите чат.")
    print("")
    term.setTextColor(colors.lightGray)
    print("Нажмите любую клавишу...")
    os.pullEvent("key")
    return 1
end

nickname = nickname or myLabel()
print("Чат ЗнатокOS. Ник: " .. nickname .. ". /quit для выхода.")
print("Отправитель: компьютер #" .. myId())
print(string.rep("-", 30))

-- Цикл приёма сообщений: выводит их с цветовой подсветкой ника.
local function recvCo()
    while true do
        local msg = receive("znatokos.chat")
        if msg then
            term.setTextColor(colors.lime)
            io.write("\n<" .. (msg.payload.nick or "?") .. "@" .. msg.from .. "> ")
            term.setTextColor(colors.white)
            io.write(tostring(msg.payload.text) .. "\n> ")
        end
    end
end

-- Цикл отправки: считывает строки и шлёт их broadcast.
local function sendCo()
    while true do
        io.write("> ")
        local line = read()
        if line == "/quit" then return end
        if line and #line > 0 then
            broadcast("znatokos.chat", { nick = nickname, text = line })
        end
    end
end

parallel.waitForAny(recvCo, sendCo)
return 0
