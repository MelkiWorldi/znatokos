-- Змейка — классика. Стрелки = управление, q/Esc = выход.
local theme = znatokos.use("ui/theme")
local text  = znatokos.use("util/text")

return function()
    local th = theme.get()
    local w, h = term.getSize()
    h = h - 1  -- строка для счёта
    local snake = { { x = math.floor(w / 2), y = math.floor(h / 2) } }
    local dir = { x = 1, y = 0 }
    local food = { x = math.random(1, w), y = math.random(1, h) }
    local score, alive = 0, true

    local function drawFrame()
        term.setBackgroundColor(th.bg); term.clear()
        term.setBackgroundColor(colors.red)
        term.setCursorPos(food.x, food.y); term.write(" ")
        term.setBackgroundColor(colors.lime)
        for _, s in ipairs(snake) do
            term.setCursorPos(s.x, s.y); term.write(" ")
        end
        term.setBackgroundColor(th.bg); term.setTextColor(th.accent)
        term.setCursorPos(1, h + 1)
        term.write("Счёт: " .. score .. "  стрелки / q")
    end

    local function tick()
        local head = snake[1]
        local nx, ny = head.x + dir.x, head.y + dir.y
        if nx < 1 or nx > w or ny < 1 or ny > h then alive = false; return end
        for _, s in ipairs(snake) do
            if s.x == nx and s.y == ny then alive = false; return end
        end
        table.insert(snake, 1, { x = nx, y = ny })
        if nx == food.x and ny == food.y then
            score = score + 1
            food = { x = math.random(1, w), y = math.random(1, h) }
        else
            table.remove(snake)
        end
    end

    while alive do
        drawFrame()
        local timer = os.startTimer(0.2)
        while true do
            local ev, p = os.pullEvent()
            if ev == "timer" and p == timer then break end
            if ev == "key" then
                if p == keys.up    and dir.y == 0 then dir = { x = 0, y = -1 }
                elseif p == keys.down  and dir.y == 0 then dir = { x = 0, y = 1 }
                elseif p == keys.left  and dir.x == 0 then dir = { x = -1, y = 0 }
                elseif p == keys.right and dir.x == 0 then dir = { x = 1, y = 0 }
                elseif p == keys.q or p == keys.escape then return
                end
            elseif ev == "znatokos:resize" or ev == "term_resize" then
                w, h = term.getSize(); h = h - 1
            end
        end
        tick()
    end

    term.setBackgroundColor(th.bg); term.clear()
    local msg = "Игра окончена. Счёт: " .. score
    term.setCursorPos(math.floor((w - text.len(msg)) / 2) + 1,
                      math.floor(h / 2) + 1)
    term.setTextColor(colors.red); term.write(msg)
    term.setTextColor(th.fg)
    local hint = "q — выход, любая клавиша — новая игра"
    term.setCursorPos(math.max(1, math.floor((w - text.len(hint)) / 2) + 1),
                      math.floor(h / 2) + 3)
    term.write(hint)
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.q or key == keys.escape then return end
        if key == keys.enter or key == keys.space then
            -- для простоты: выход, пользователь откроет заново
            return
        end
    end
end
