-- Интерактивный Lua REPL. Выход: exit или Ctrl+D.
return function(args, ctx)
    print("Lua REPL. Введите 'exit' для выхода.")
    local env = setmetatable({ print = print }, { __index = _G, __newindex = _G })
    while true do
        io.write("lua> ")
        local line = read()
        if not line or line == "exit" then return 0 end
        local fn, err = load("return " .. line, "repl", "t", env)
        if not fn then fn, err = load(line, "repl", "t", env) end
        if not fn then
            print("!syntax: " .. tostring(err))
        else
            local ok, res = pcall(fn)
            if not ok then print("!error: " .. tostring(res))
            elseif res ~= nil then print(textutils.serialize(res)) end
        end
    end
end
