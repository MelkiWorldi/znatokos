-- passwd [user]
local users = znatokos.use("auth/users")
local vfs   = znatokos.use("fs/vfs")
return function(args)
    local target = args[2] or vfs.getUser().user
    if target ~= vfs.getUser().user and vfs.getUser().uid ~= 0 then
        print("Отказано: только root может менять чужой пароль."); return 1
    end
    if target ~= vfs.getUser().user then
        io.write("Новый пароль для " .. target .. ": ")
        local p1 = read("*"); io.write("Повторите: "); local p2 = read("*")
        if p1 ~= p2 then print("Пароли не совпадают."); return 1 end
        users.setPassword(target, p1)
        print("Пароль изменён.")
    else
        io.write("Старый пароль: "); local old = read("*")
        if not users.verify(target, old) then print("Неверно."); return 1 end
        io.write("Новый: "); local p1 = read("*")
        io.write("Повторите: "); local p2 = read("*")
        if p1 ~= p2 then print("Пароли не совпадают."); return 1 end
        users.setPassword(target, p1); print("Пароль изменён.")
    end
    return 0
end
