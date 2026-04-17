-- kill <pid>
local sched = znatokos.use("kernel/scheduler")
return function(args)
    local pid = tonumber(args[2])
    if not pid then print("Использование: kill <pid>"); return 1 end
    if sched.kill(pid) then print("Задача " .. pid .. " завершена.")
    else print("Нет задачи: " .. pid); return 1 end
    return 0
end
