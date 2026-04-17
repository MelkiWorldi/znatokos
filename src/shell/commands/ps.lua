-- ps — список задач
local sched = znatokos.use("kernel/scheduler")
return function()
    print(("%-5s %-15s %-8s %s"):format("PID", "NAME", "OWNER", "STATUS"))
    for _, t in ipairs(sched.list()) do
        print(("%-5d %-15s %-8s %s"):format(t.pid, t.name:sub(1, 15), t.owner, t.status))
    end
    return 0
end
