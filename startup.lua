-- ЗнатокOS: автозагрузка
-- Этот файл копируется установщиком в корень диска как /startup.lua
local ok, err = pcall(function()
    shell.run("/znatokos/src/kernel/boot.lua")
end)
if not ok then
    term.setTextColor(colors.red)
    print("ЗнатокOS: сбой загрузки: " .. tostring(err))
    term.setTextColor(colors.white)
    print("Переходим к стандартному шеллу CraftOS.")
end
