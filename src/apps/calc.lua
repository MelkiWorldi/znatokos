-- Калькулятор с кнопочным интерфейсом.
local theme   = znatokos.use("ui/theme")
local widgets = znatokos.use("ui/widgets")

return function()
    local th = theme.get()
    local display = "0"
    local buffer = nil
    local op = nil
    local resetOnDigit = false

    local function push(digit)
        if resetOnDigit then display = ""; resetOnDigit = false end
        if display == "0" and digit ~= "." then display = "" end
        display = display .. digit
    end

    local function applyOp()
        local n = tonumber(display) or 0
        if op == "+" then display = tostring(buffer + n)
        elseif op == "-" then display = tostring(buffer - n)
        elseif op == "*" then display = tostring(buffer * n)
        elseif op == "/" then display = (n ~= 0 and tostring(buffer / n) or "ERR") end
    end

    local function draw()
        term.setBackgroundColor(th.bg); term.clear()
        -- дисплей
        term.setBackgroundColor(colors.black); term.setTextColor(colors.lime)
        local w = term.getSize()
        for i = 1, 3 do term.setCursorPos(1, i); term.write(string.rep(" ", w)) end
        term.setCursorPos(w - #display, 2); term.write(display)
        -- кнопки
        local grid = {
            {"7","8","9","/"},
            {"4","5","6","*"},
            {"1","2","3","-"},
            {"0",".","=","+"},
            {"C"},
        }
        local btns = {}
        for r, row in ipairs(grid) do
            for c, label in ipairs(row) do
                local x = 1 + (c - 1) * 6
                local y = 4 + (r - 1) * 2
                local b = widgets.button({ x = x, y = y, w = 5, label = label })
                b:draw(term)
                btns[#btns + 1] = b
            end
        end
        return btns
    end

    local function press(label)
        if label:match("%d") then push(label)
        elseif label == "." then push(".")
        elseif label == "C" then display = "0"; buffer = nil; op = nil
        elseif label == "=" then
            if op and buffer then applyOp(); op = nil; buffer = nil; resetOnDigit = true end
        else
            if op and buffer then applyOp() end
            buffer = tonumber(display) or 0
            op = label; resetOnDigit = true
        end
    end

    while true do
        local btns = draw()
        local ev = { os.pullEvent() }
        if ev[1] == "mouse_click" then
            for _, b in ipairs(btns) do
                if b:hit(ev[3], ev[4]) then press(b.label); break end
            end
        elseif ev[1] == "char" then
            if ev[2]:match("[0-9%.]") then press(ev[2])
            elseif ev[2] == "+" or ev[2] == "-" or ev[2] == "*" or ev[2] == "/" then press(ev[2])
            elseif ev[2] == "=" then press("=")
            elseif ev[2] == "c" or ev[2] == "C" then press("C")
            end
        elseif ev[1] == "key" then
            if ev[2] == keys.enter then press("=")
            elseif ev[2] == keys.q then return
            elseif ev[2] == keys.backspace then
                display = #display > 1 and display:sub(1, -2) or "0"
            end
        end
    end
end
