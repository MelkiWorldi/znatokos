-- net — информация о сети.
local net = znatokos.use("net/rednet")
return function(args)
    local sub = args[2]
    if sub == "discover" or not sub then
        if not net.ensureOpen() then print("Нет модема."); return 1 end
        print("Компьютер #" .. net.id() .. " (" .. net.label() .. ")")
        print("Поиск хостов...")
        local hosts = net.discover(2)
        if #hosts == 0 then print("Никого не найдено.")
        else
            for _, h in ipairs(hosts) do print(("  #%d  %s"):format(h.id, h.label)) end
        end
    elseif sub == "label" then
        if args[3] then os.setComputerLabel(args[3]); print("Метка: " .. args[3])
        else print(net.label()) end
    else
        print("net [discover|label [имя]]")
    end
    return 0
end
