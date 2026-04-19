-- Реестр возможностей (capabilities) ЗнатокOS.
-- Приложение запрашивает набор прав в manifest; пользователь/система решают, выдать ли их.
-- dangerous=true означает, что возможность требует явного подтверждения при выдаче.

local M = {}

M.ALL = {
    ["ui.window"] = {
        id = "ui.window",
        label = "Окно",
        description = "Создавать графическое окно и перехватывать ввод в нём",
        dangerous = false,
    },
    ["fs.home"] = {
        id = "fs.home",
        label = "Домашний каталог",
        description = "Читать и писать только в ~/ (домашнюю папку пользователя)",
        dangerous = false,
    },
    ["fs.all"] = {
        id = "fs.all",
        label = "Вся файловая система",
        description = "Читать и писать по любому пути в FS, включая системные файлы",
        dangerous = true,
    },
    ["net.rednet"] = {
        id = "net.rednet",
        label = "Локальная сеть (rednet)",
        description = "Отправлять и принимать пакеты rednet через модемы",
        dangerous = false,
    },
    ["net.http"] = {
        id = "net.http",
        label = "Интернет (HTTP)",
        description = "Выполнять http.get и http.post в внешнюю сеть",
        dangerous = true,
    },
    ["net.rpc"] = {
        id = "net.rpc",
        label = "RPC",
        description = "Вызывать и регистрировать удалённые процедуры между компьютерами",
        dangerous = false,
    },
    ["periph.list"] = {
        id = "periph.list",
        label = "Список периферии",
        description = "Получать список подключённых устройств и их типы",
        dangerous = false,
    },
    ["periph.redstone"] = {
        id = "periph.redstone",
        label = "Редстоун",
        description = "Читать и выставлять редстоун-сигналы на сторонах компьютера",
        dangerous = false,
    },
    ["periph.inventory"] = {
        id = "periph.inventory",
        label = "Инвентарь",
        description = "Читать и изменять содержимое сундуков, бочек и прочих хранилищ",
        dangerous = false,
    },
    ["periph.speaker"] = {
        id = "periph.speaker",
        label = "Колонка",
        description = "Воспроизводить звуки, ноты и DFPWM-аудио через speaker peripheral",
        dangerous = false,
    },
    ["periph.advanced"] = {
        id = "periph.advanced",
        label = "Advanced Peripherals",
        description = "Использовать периферию из мода Advanced Peripherals",
        dangerous = false,
    },
    ["periph.bridge"] = {
        id = "periph.bridge",
        label = "CC:Bridge",
        description = "Использовать периферию из мода CC:Bridge",
        dangerous = false,
    },
    ["periph.logistics"] = {
        id = "periph.logistics",
        label = "CC Total Logistics",
        description = "Использовать периферию из мода CC Total Logistics",
        dangerous = false,
    },
    ["system.shutdown"] = {
        id = "system.shutdown",
        label = "Выключение системы",
        description = "Вызывать os.reboot и os.shutdown",
        dangerous = true,
    },
    ["kernel.spawn"] = {
        id = "kernel.spawn",
        label = "Запуск задач",
        description = "Создавать сиблинг-задачи через sched.spawn",
        dangerous = true,
    },
}

-- Проверка: существует ли capability с таким ID
function M.isValid(capId)
    return M.ALL[capId] ~= nil
end

-- Описание одной capability
function M.describe(capId)
    local c = M.ALL[capId]
    if not c then return nil end
    return { id = c.id, label = c.label, description = c.description, dangerous = c.dangerous }
end

-- Все ID в отсортированном порядке
function M.listAll()
    local out = {}
    for id in pairs(M.ALL) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-- Строка для показа пользователю: "ui.window, net.http (опасно), fs.home"
function M.formatList(caps)
    if not caps or #caps == 0 then return "(нет)" end
    local parts = {}
    for i = 1, #caps do
        local id = caps[i]
        local c = M.ALL[id]
        if c then
            if c.dangerous then
                parts[#parts + 1] = id .. " (опасно)"
            else
                parts[#parts + 1] = id
            end
        else
            parts[#parts + 1] = id .. " (?)"
        end
    end
    return table.concat(parts, ", ")
end

return M
