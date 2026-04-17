-- top — живой монитор задач. Выход: q
local sched = znatokos.use("kernel/scheduler")
local theme = znatokos.use("ui/theme")
return function()
    local th = theme.get()
    local running = true
    while running do
        term.setBackgroundColor(th.bg); term.clear(); term.setCursorPos(1, 1)
        term.setTextColor(th.accent)
        print("top — Ctrl+C или q для выхода.  Задач: " .. sched.count())
        term.setTextColor(th.fg)
        print(("%-5s %-18s %-8s %-10s %s"):format("PID", "NAME", "OWNER", "STATUS", "STARTED"))
        for _, t in ipairs(sched.list()) do
            print(("%-5d %-18s %-8s %-10s %.1fs ago"):format(
                t.pid, t.name:sub(1, 18), t.owner, t.status, os.clock() - (t.started or os.clock())))
        end
        local timer = os.startTimer(1)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "key" and (p1 == keys.q) then running = false; break end
            if ev == "timer" and p1 == timer then break end
        end
    end
    return 0
end
