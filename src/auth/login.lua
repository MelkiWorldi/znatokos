-- Экран входа. Адаптивный: вписывается в любой размер ≥ 20×10.
local users   = znatokos.use("auth/users")
local theme   = znatokos.use("ui/theme")
local widgets = znatokos.use("ui/widgets")
local focus   = znatokos.use("ui/focus")
local text    = znatokos.use("util/text")

local M = {}

local function drawFrame(title)
    local th = theme.get()
    local sw, sh = term.getSize()
    term.setBackgroundColor(th.bg); term.clear()
    -- Заголовок «ЗнатокOS» в верхней части
    term.setTextColor(th.accent); term.setBackgroundColor(th.bg)
    local header = "ЗнатокOS"
    term.setCursorPos(math.floor((sw - text.len(header)) / 2) + 1, math.max(1, math.floor(sh / 4)))
    term.write(header)
    -- Подзаголовок
    if title then
        term.setTextColor(th.fg)
        local sub = title
        term.setCursorPos(math.floor((sw - text.len(sub)) / 2) + 1, math.max(2, math.floor(sh / 4) + 1))
        term.write(sub)
    end
end

local function msgLine(y, s, col)
    local sw = term.getSize()
    term.setTextColor(col or theme.get().fg)
    term.setBackgroundColor(theme.get().bg)
    term.setCursorPos(math.floor((sw - text.len(s)) / 2) + 1, y)
    term.write(s)
end

--------------------------------------------------------------
-- Первый запуск: создаём root
--------------------------------------------------------------
local function firstRunSetup()
    while true do
        drawFrame("Первый запуск — создайте пароль root")
        local sw, sh = term.getSize()
        local midY = math.floor(sh / 2)
        local fieldW = math.min(30, sw - 4)
        local fieldX = math.floor((sw - fieldW) / 2) + 1

        msgLine(midY, "Пароль:")
        local inp1 = widgets.input({
            x = fieldX, y = midY + 1, w = fieldW, mask = "*",
        })
        msgLine(midY + 3, "Повторите:")
        local inp2 = widgets.input({
            x = fieldX, y = midY + 4, w = fieldW, mask = "*",
        })
        local btn = widgets.button({
            x = math.floor((sw - 10) / 2) + 1, y = midY + 6, w = 10, label = "Создать",
            onClick = function() _G._dialog_result = "submit" end,
        })
        inp1:draw(); inp2:draw(); btn:draw()
        local widgets_list = { inp1, inp2, btn }
        local current = inp1
        inp1:onFocus()

        while true do
            local ev = { os.pullEvent() }
            if ev[1] == "key" then
                if ev[2] == keys.tab then
                    local handled, nxt = focus.handleKey(widgets_list, current, keys.tab, false)
                    if handled then current = nxt end
                elseif ev[2] == keys.enter then
                    if current == inp1 then
                        current:onBlur(); current = inp2; inp2:onFocus()
                    elseif current == inp2 or current == btn then
                        _G._dialog_result = "submit"
                    end
                end
            end
            if current then current:event(ev) end
            if _G._dialog_result == "submit" then
                _G._dialog_result = nil
                if inp1.value == inp2.value and text.len(inp1.value) > 0 then
                    local ok, err = users.create("root", inp1.value, { uid = 0, gid = 0 })
                    if ok then
                        drawFrame("Готово — войдите как root")
                        sleep(1)
                        return
                    else
                        msgLine(midY + 8, "Ошибка: " .. tostring(err), colors.red); sleep(2)
                    end
                else
                    msgLine(midY + 8, "Пароли не совпадают", colors.red); sleep(1.5)
                end
                break  -- перерисуем форму
            end
        end
    end
end

--------------------------------------------------------------
-- Основной login
--------------------------------------------------------------
function M.run()
    if users.isEmpty() then firstRunSetup() end

    while true do
        drawFrame("Вход")
        local sw, sh = term.getSize()
        local midY = math.floor(sh / 2)
        local fieldW = math.min(30, sw - 4)
        local fieldX = math.floor((sw - fieldW) / 2) + 1

        msgLine(midY, "Пользователь:")
        local inpUser = widgets.input({ x = fieldX, y = midY + 1, w = fieldW })
        msgLine(midY + 3, "Пароль:")
        local inpPass = widgets.input({ x = fieldX, y = midY + 4, w = fieldW, mask = "*" })
        local btnOk = widgets.button({
            x = math.floor((sw - 10) / 2) + 1, y = midY + 6, w = 10, label = "Войти",
            onClick = function() _G._dialog_result = "submit" end,
        })
        inpUser:draw(); inpPass:draw(); btnOk:draw()
        local items = { inpUser, inpPass, btnOk }
        local current = inpUser
        inpUser:onFocus()

        while true do
            local ev = { os.pullEvent() }
            if ev[1] == "key" then
                if ev[2] == keys.tab then
                    local handled, nxt = focus.handleKey(items, current, keys.tab, false)
                    if handled then current = nxt end
                elseif ev[2] == keys.enter then
                    if current == inpUser then
                        current:onBlur(); current = inpPass; inpPass:onFocus()
                    elseif current == inpPass or current == btnOk then
                        _G._dialog_result = "submit"
                    end
                end
            end
            if current then current:event(ev) end
            if _G._dialog_result == "submit" then
                _G._dialog_result = nil
                local name = inpUser.value
                if name ~= "" and users.verify(name, inpPass.value) then
                    return users.get(name)
                else
                    msgLine(midY + 8, "Неверный логин или пароль", colors.red); sleep(1.5)
                    break
                end
            end
        end
    end
end

return M
