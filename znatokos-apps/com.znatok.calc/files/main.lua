-- Калькулятор с кнопочным интерфейсом. Адаптивная сетка кнопок.
-- Точка входа приложения в манифест-формате ZnatokOS v0.3.0.
local theme   = znatokos.use("ui/theme")
local widgets = znatokos.use("ui/widgets")
local text    = znatokos.use("util/text")

-- Получаем текущего пользователя: сначала из контекста приложения,
-- иначе — напрямую из VFS (резервный вариант).
local user = (znatokos.app and znatokos.app.user)
         or (znatokos.use("fs/vfs").getUser() or { user = "guest" })

local th = theme.get()
local display = "0"
local buffer, op, reset = nil, nil, false

-- Добавить символ к дисплею (с учётом сброса после операции)
local function push(d)
    if reset then display = ""; reset = false end
    if display == "0" and d ~= "." then display = "" end
    display = display .. d
end

-- Применить отложенную арифметическую операцию к буферу и дисплею
local function applyOp()
    local n = tonumber(display) or 0
    if op == "+" then display = tostring(buffer + n)
    elseif op == "-" then display = tostring(buffer - n)
    elseif op == "*" then display = tostring(buffer * n)
    elseif op == "/" then display = (n ~= 0 and tostring(buffer / n) or "ERR") end
end

-- Обработка нажатия виртуальной/физической кнопки
local function press(label)
    if label:match("%d") then push(label)
    elseif label == "." then push(".")
    elseif label == "C" then display = "0"; buffer = nil; op = nil
    elseif label == "=" then
        if op and buffer then applyOp(); op = nil; buffer = nil; reset = true end
    else
        if op and buffer then applyOp() end
        buffer = tonumber(display) or 0
        op = label; reset = true
    end
end

-- Отрисовка интерфейса: дисплей сверху + сетка кнопок 4×5
local function render()
    local w, h = term.getSize()
    term.setBackgroundColor(th.bg); term.clear()
    -- дисплей
    term.setBackgroundColor(colors.black); term.setTextColor(colors.lime)
    for r = 1, 2 do term.setCursorPos(1, r); term.write(string.rep(" ", w)) end
    term.setCursorPos(math.max(1, w - #display), 2); term.write(display)
    -- сетка кнопок 4×5
    local grid = {
        {"7","8","9","/"},
        {"4","5","6","*"},
        {"1","2","3","-"},
        {"0",".","=","+"},
        {"C"},
    }
    local btns = {}
    local cellW = math.max(3, math.floor(w / 4))
    local cellH = math.max(1, math.floor((h - 3) / 5))
    for r, row in ipairs(grid) do
        for c, label in ipairs(row) do
            local bx = 1 + (c - 1) * cellW
            local by = 3 + (r - 1) * cellH
            local b = widgets.button({ x = bx, y = by, w = cellW - 1, h = cellH, label = label })
            b:draw(term)
            btns[#btns + 1] = b
        end
    end
    return btns
end

-- Основной цикл обработки событий
while true do
    local btns = render()
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" and ev[2] == 1 then
        for _, b in ipairs(btns) do
            if widgets.hit(b, ev[3], ev[4]) then press(b.label); break end
        end
    elseif ev[1] == "char" then
        local ch = ev[2]
        if ch:match("[0-9%.]") or ch == "+" or ch == "-" or ch == "*" or ch == "/" then
            press(ch)
        elseif ch == "=" then press("=")
        elseif ch == "c" or ch == "C" then press("C")
        end
    elseif ev[1] == "key" then
        if ev[2] == keys.enter then press("=")
        elseif ev[2] == keys.q or ev[2] == keys.escape then return
        elseif ev[2] == keys.backspace then
            display = #display > 1 and display:sub(1, -2) or "0"
        end
    elseif ev[1] == "znatokos:resize" or ev[1] == "term_resize" then
        -- re-render в следующей итерации
    end
end
