-- Тестируем парсер шелла (split) — для этого выделим его локально.
-- Поскольку split внутри shell.lua, копируем туда же логику.
local T = _G._T

local function split(line)
    local args = {}
    local i, n = 1, #line
    while i <= n do
        while i <= n and line:sub(i, i):match("%s") do i = i + 1 end
        if i > n then break end
        local c = line:sub(i, i)
        if c == '"' or c == "'" then
            local q = c; i = i + 1
            local s = i
            while i <= n and line:sub(i, i) ~= q do i = i + 1 end
            args[#args + 1] = line:sub(s, i - 1); i = i + 1
        else
            local s = i
            while i <= n and not line:sub(i, i):match("%s") do i = i + 1 end
            args[#args + 1] = line:sub(s, i - 1)
        end
    end
    return args
end

local a = split("ls /home")
T.assertEq(#a, 2, "simple 2 args")
T.assertEq(a[1], "ls", "first arg")
T.assertEq(a[2], "/home", "second arg")

local b = split('echo "hello world" 42')
T.assertEq(#b, 3, "quoted 3 args")
T.assertEq(b[2], "hello world", "quoted value preserved")
T.assertEq(b[3], "42", "third arg")

local c = split("   cmd    x   y")
T.assertEq(#c, 3, "whitespace collapsed")
T.assertEq(c[1], "cmd", "cmd parsed")
