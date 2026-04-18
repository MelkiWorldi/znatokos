-- Часы — большие цифры. q или Esc = выход.
local theme = znatokos.use("ui/theme")
local text  = znatokos.use("util/text")

local DIGITS = {
    ["0"] = {"###","# #","# #","# #","###"},
    ["1"] = {"  #","  #","  #","  #","  #"},
    ["2"] = {"###","  #","###","#  ","###"},
    ["3"] = {"###","  #","###","  #","###"},
    ["4"] = {"# #","# #","###","  #","  #"},
    ["5"] = {"###","#  ","###","  #","###"},
    ["6"] = {"###","#  ","###","# #","###"},
    ["7"] = {"###","  #","  #","  #","  #"},
    ["8"] = {"###","# #","###","# #","###"},
    ["9"] = {"###","# #","###","  #","###"},
    [":"] = {"   "," # ","   "," # ","   "},
}

return function()
    local th = theme.get()
    while true do
        local w, h = term.getSize()
        term.setBackgroundColor(th.bg); term.clear()
        local t = textutils.formatTime(os.time(), true)
        local lines = {"", "", "", "", ""}
        for i = 1, #t do
            local d = DIGITS[t:sub(i, i)] or {"   ","   ","   ","   ","   "}
            for r = 1, 5 do lines[r] = lines[r] .. d[r] .. " " end
        end
        local startY = math.max(1, math.floor((h - 5) / 2))
        term.setTextColor(th.accent)
        for r, l in ipairs(lines) do
            term.setCursorPos(math.max(1, math.floor((w - #l) / 2) + 1), startY + r - 1)
            term.write(l)
        end
        term.setTextColor(th.fg)
        local dateStr = "День " .. os.day()
        term.setCursorPos(math.floor((w - text.len(dateStr)) / 2) + 1, startY + 7)
        term.write(dateStr)
        local hint = "q для выхода"
        term.setCursorPos(math.floor((w - text.len(hint)) / 2) + 1, h)
        term.setTextColor(colors.gray); term.write(hint)

        local timer = os.startTimer(1)
        while true do
            local ev, p = os.pullEvent()
            if ev == "timer" and p == timer then break end
            if ev == "key" and (p == keys.q or p == keys.escape) then return end
            if ev == "znatokos:resize" or ev == "term_resize" then break end
        end
    end
end
