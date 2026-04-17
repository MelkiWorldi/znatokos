-- useradd <имя>
local users = znatokos.use("auth/users")
local vfs   = znatokos.use("fs/vfs")
return function(args)
    if vfs.getUser().uid ~= 0 then print("Только root может добавлять пользователей."); return 1 end
    if not args[2] then print("Использование: useradd <имя>"); return 1 end
    io.write("Пароль: "); local p1 = read("*")
    io.write("Повторите: "); local p2 = read("*")
    if p1 ~= p2 then print("Пароли не совпадают."); return 1 end
    local ok, err = users.create(args[2], p1)
    if not ok then print("Ошибка: " .. err); return 1 end
    print("Пользователь создан: " .. args[2])
    return 0
end
