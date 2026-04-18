-- Paint: рисование цветных пикселей. ЛКМ — рисовать, ПКМ — ластик,
-- цифры 0-9 — выбор цвета, s — сохранить, q — выход.
-- Файл рисунка сохраняется в домашнюю папку текущего пользователя.

local user = (znatokos.app and znatokos.app.user)
         or (znatokos.use("fs/vfs").getUser() or { user = "guest", home = "/znatokos/home/guest" })

local theme = znatokos.use("ui/theme")

-- Палитра доступных цветов (индексы 1..10 соответствуют клавишам 1..9,0)
local PALETTE = {
    colors.white, colors.orange, colors.magenta, colors.lightBlue,
    colors.yellow, colors.lime, colors.pink, colors.gray,
    colors.cyan, colors.purple,
}

local th = theme.get()
local w, h = term.getSize()
h = h - 1 -- нижняя строка зарезервирована под палитру и подсказки
local canvas = {}
for y = 1, h do canvas[y] = {} end
local current = colors.red

-- Полная перерисовка холста и нижней панели
local function draw()
    term.setBackgroundColor(th.bg); term.clear()
    for y = 1, h do
        for x = 1, w do
            if canvas[y][x] then
                term.setBackgroundColor(canvas[y][x])
                term.setCursorPos(x, y); term.write(" ")
            end
        end
    end
    -- палитра
    term.setCursorPos(1, h + 1)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    term.write(" цвет: ")
    for _, c in ipairs(PALETTE) do
        term.setBackgroundColor(c); term.write(" ")
    end
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    term.write("  s-save q-exit")
end

draw()
while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" or ev[1] == "mouse_drag" then
        local btn, x, y = ev[2], ev[3], ev[4]
        if y <= h then
            if btn == 1 then canvas[y][x] = current
            elseif btn == 2 then canvas[y][x] = nil end
            term.setBackgroundColor(canvas[y][x] or th.bg)
            term.setCursorPos(x, y); term.write(" ")
        end
    elseif ev[1] == "char" then
        local c = ev[2]
        local n = tonumber(c)
        if n and PALETTE[n == 0 and 10 or n] then
            current = PALETTE[n == 0 and 10 or n]
        elseif c == "q" then
            return
        elseif c == "s" then
            -- Сохраняем в домашнюю папку пользователя (sandbox требует путь внутри home).
            -- Формат NFP: hex-индекс цвета в каждой ячейке, пробел — прозрачность.
            local path = user.home .. "/drawing.nfp"
            local f = fs.open(path, "w")
            for y = 1, h do
                local row = {}
                for x = 1, w do
                    local col = canvas[y][x]
                    if col and col > 0 then
                        local idx = math.floor(math.log(col) / math.log(2))
                        row[x] = string.format("%x", idx)
                    else
                        row[x] = " "
                    end
                end
                f.writeLine(table.concat(row))
            end
            f.close()
        end
    end
end
