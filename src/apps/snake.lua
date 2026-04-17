-- Змейка. Стрелки для управления, q — выход.
local theme = znatokos.use("ui/theme")

return function()
    local th = theme.get()
    local w, h = term.getSize()
    h = h - 1  -- оставим строку под счёт
    local snake = { { x = math.floor(w / 2), y = math.floor(h / 2) } }
    local dir = { x = 1, y = 0 }
    local food = { x = math.random(1, w), y = math.random(1, h) }
    local score = 0
    local alive = true

    local function draw()
        term.setBackgroundColor(th.bg); term.clear()
        term.setBackgroundColor(colors.red)
        term.setCursorPos(food.x, food.y); term.write(" ")
        term.setBackgroundColor(colors.lime)
        for _, s in ipairs(snake) do
            term.setCursorPos(s.x, s.y); term.write(" ")
        end
        term.setBackgroundColor(th.bg); term.setTextColor(th.accent)
        term.setCursorPos(1, h + 1); term.write("Счёт: " .. score .. "  стрелки / q")
    end

    local function tick()
        local head = snake[1]
        local nx, ny = head.x + dir.x, head.y + dir.y
        if nx < 1 or nx > w or ny < 1 or ny > h then alive = false; return end
        for _, s in ipairs(snake) do if s.x == nx and s.y == ny then alive = false; return end end
        table.insert(snake, 1, { x = nx, y = ny })
        if nx == food.x and ny == food.y then
            score = score + 1
            food = { x = math.random(1, w), y = math.random(1, h) }
        else
            table.remove(snake)
        end
    end

    while alive do
        draw()
        local timer = os.startTimer(0.2)
        while true do
            local ev, p = os.pullEvent()
            if ev == "timer" and p == timer then break end
            if ev == "key" then
                if p == keys.up    and dir.y == 0 then dir = { x = 0, y = -1 }
                elseif p == keys.down  and dir.y == 0 then dir = { x = 0, y = 1 }
                elseif p == keys.left  and dir.x == 0 then dir = { x = -1, y = 0 }
                elseif p == keys.right and dir.x == 0 then dir = { x = 1, y = 0 }
                elseif p == keys.q then return
                end
            end
        end
        tick()
    end

    term.setBackgroundColor(th.bg); term.clear()
    term.setCursorPos(1, 1); term.setTextColor(colors.red)
    print("Игра окончена. Счёт: " .. score)
    term.setTextColor(th.fg)
    print("Нажмите любую клавишу.")
    os.pullEvent("key")
end
