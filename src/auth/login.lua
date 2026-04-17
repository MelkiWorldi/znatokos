-- Экран входа в ЗнатокOS.
local users = znatokos.use("auth/users")
local theme = znatokos.use("ui/theme")

local M = {}

local function centered(y, text, col)
    local w, _ = term.getSize()
    term.setCursorPos(math.max(1, math.floor((w - #text) / 2) + 1), y)
    if col then term.setTextColor(col) end
    term.write(text)
end

local function firstRunSetup()
    local t = theme.get()
    term.setBackgroundColor(t.bg); term.clear()
    local sw, sh = term.getSize()
    centered(math.floor(sh / 2) - 3, "Добро пожаловать в ЗнатокOS!", colors.yellow)
    centered(math.floor(sh / 2) - 1, "Создадим учётную запись root.", colors.white)
    term.setTextColor(colors.white)
    while true do
        centered(math.floor(sh / 2) + 1, "Пароль для root:", colors.lightGray)
        term.setCursorPos(math.floor(sw / 2) - 8, math.floor(sh / 2) + 2)
        local p1 = read("*")
        term.setCursorPos(1, math.floor(sh / 2) + 3)
        term.clearLine()
        centered(math.floor(sh / 2) + 3, "Повторите:", colors.lightGray)
        term.setCursorPos(math.floor(sw / 2) - 8, math.floor(sh / 2) + 4)
        local p2 = read("*")
        if p1 == p2 and #p1 > 0 then
            local ok, err = users.create("root", p1, { uid = 0, gid = 0 })
            if not ok then
                centered(math.floor(sh / 2) + 6, "Ошибка: " .. err, colors.red)
                sleep(2)
            else
                centered(math.floor(sh / 2) + 6, "Готово. Войдите как root.", colors.lime)
                sleep(1.5)
                return
            end
        else
            term.setCursorPos(1, math.floor(sh / 2) + 6)
            term.clearLine()
            centered(math.floor(sh / 2) + 6, "Пароли не совпадают или пусты.", colors.red)
            sleep(1.5)
            term.setCursorPos(1, math.floor(sh / 2) + 6); term.clearLine()
        end
    end
end

function M.run()
    if users.isEmpty() then firstRunSetup() end

    local t = theme.get()
    while true do
        term.setBackgroundColor(t.bg); term.clear()
        local sw, sh = term.getSize()
        centered(math.floor(sh / 2) - 3, "┌─────────────────────────┐", colors.cyan)
        centered(math.floor(sh / 2) - 2, "│       ЗнатокOS          │", colors.cyan)
        centered(math.floor(sh / 2) - 1, "└─────────────────────────┘", colors.cyan)
        centered(math.floor(sh / 2) + 1, "Пользователь:", colors.white)
        term.setCursorPos(math.floor(sw / 2) - 8, math.floor(sh / 2) + 2)
        term.setTextColor(colors.yellow)
        local name = read()
        if name == "" then
            -- ничего не ввели — повторяем
        else
            centered(math.floor(sh / 2) + 3, "Пароль:", colors.white)
            term.setCursorPos(math.floor(sw / 2) - 8, math.floor(sh / 2) + 4)
            local pass = read("*")
            if users.verify(name, pass) then
                local u = users.get(name)
                return u
            else
                centered(math.floor(sh / 2) + 6, "Неверный логин или пароль.", colors.red)
                sleep(1.5)
            end
        end
    end
end

return M
