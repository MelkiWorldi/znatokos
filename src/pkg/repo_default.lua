-- Встроенный каталог пакетов. Используется как fallback когда http недоступен.
-- Файлы пакетов хранятся как inline-строки. Прост, но работоспособен.
return {
    updated = "2026-01-01",
    packages = {
        ["hello"] = {
            name = "hello", version = "1.0.0",
            description = "Пример: программа, печатающая приветствие",
            files = {
                {
                    path = "/home/hello.lua",
                    content = [[
print("Привет от ЗнатокOS!")
print("Это встроенный пример из pkg.")
]]
                },
            },
        },
        ["guess"] = {
            name = "guess", version = "1.0.0",
            description = "Игра «Угадай число»",
            files = {
                {
                    path = "/home/guess.lua",
                    content = [[
local secret = math.random(1, 100)
print("Я загадал число от 1 до 100. Угадай!")
while true do
    io.write("> ")
    local n = tonumber(read())
    if not n then print("Нужно число.")
    elseif n < secret then print("Больше.")
    elseif n > secret then print("Меньше.")
    else print("Угадал!"); break end
end
]]
                },
            },
        },
        ["sysinfo"] = {
            name = "sysinfo", version = "1.0.0",
            description = "Сведения о системе",
            files = {
                {
                    path = "/home/sysinfo.lua",
                    content = [[
print("ЗнатокOS v" .. (_G.znatokos and _G.znatokos.VERSION or "?"))
print("Computer #" .. os.getComputerID())
print("Label: " .. (os.getComputerLabel() or "(нет)"))
local w, h = term.getSize()
print("Экран: " .. w .. "x" .. h)
print("Цветной: " .. tostring(term.isColor()))
print("Uptime: " .. math.floor(os.clock()) .. "с")
]]
                },
            },
        },
    },
}
