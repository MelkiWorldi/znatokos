-- Часы. Крупные цифры из символов.
local theme = znatokos.use("ui/theme")

local DIGITS = {
    ["0"] = {"███","█ █","█ █","█ █","███"},
    ["1"] = {"  █","  █","  █","  █","  █"},
    ["2"] = {"███","  █","███","█  ","███"},
    ["3"] = {"███","  █","███","  █","███"},
    ["4"] = {"█ █","█ █","███","  █","  █"},
    ["5"] = {"███","█  ","███","  █","███"},
    ["6"] = {"███","█  ","███","█ █","███"},
    ["7"] = {"███","  █","  █","  █","  █"},
    ["8"] = {"███","█ █","███","█ █","███"},
    ["9"] = {"███","█ █","███","  █","███"},
    [":"] = {"   "," █ ","   "," █ ","   "},
}

return function()
    local th = theme.get()
    while true do
        term.setBackgroundColor(th.bg); term.clear()
        local w, h = term.getSize()
        local t = textutils.formatTime(os.time(), true)
        local lines = {"", "", "", "", ""}
        for c in t:gmatch(".") do
            local d = DIGITS[c] or {"   ","   ","   ","   ","   "}
            for i = 1, 5 do lines[i] = lines[i] .. d[i] .. " " end
        end
        local startY = math.floor((h - 5) / 2)
        term.setTextColor(th.accent)
        for i, l in ipairs(lines) do
            term.setCursorPos(math.max(1, math.floor((w - #l) / 2) + 1), startY + i)
            term.write(l)
        end
        term.setTextColor(th.fg)
        term.setCursorPos(math.max(1, math.floor(w / 2 - 3)), startY + 7)
        term.write("День " .. os.day())
        local timer = os.startTimer(1)
        while true do
            local ev, p = os.pullEvent()
            if ev == "timer" and p == timer then break end
            if ev == "key" and p == keys.q then return end
            if ev == "mouse_click" then return end
        end
    end
end
