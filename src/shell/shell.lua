-- Интерактивный шелл ЗнатокOS.
-- Поддерживает: историю (↑↓), autocomplete (Tab) команд и путей,
-- парсинг аргументов с кавычками, alias, перенаправление вывода нет (упрощённо).
local theme    = znatokos.use("ui/theme")
local builtins = znatokos.use("shell/builtins")
local vfs      = znatokos.use("fs/vfs")
local paths    = znatokos.use("fs/paths")

local M = {}

local function split(line)
    local args = {}
    local i, n = 1, #line
    while i <= n do
        while i <= n and line:sub(i, i):match("%s") do i = i + 1 end
        if i > n then break end
        local c = line:sub(i, i)
        if c == '"' or c == "'" then
            local quote = c; i = i + 1
            local start = i
            while i <= n and line:sub(i, i) ~= quote do i = i + 1 end
            args[#args + 1] = line:sub(start, i - 1)
            i = i + 1
        else
            local start = i
            while i <= n and not line:sub(i, i):match("%s") do i = i + 1 end
            args[#args + 1] = line:sub(start, i - 1)
        end
    end
    return args
end

local function completions(prefix, cwd)
    local out = {}
    -- команды, если это первое слово
    for _, name in ipairs(builtins.list()) do
        if name:sub(1, #prefix) == prefix then out[#out + 1] = name end
    end
    -- пути
    local dir, base
    if prefix:find("/") then
        dir = prefix:match("^(.*)/[^/]*$") or "/"
        base = prefix:match("/([^/]*)$") or ""
    else
        dir = cwd; base = prefix
    end
    local full = dir == "" and cwd or dir
    if full:sub(1, 1) ~= "/" then full = fs.combine(cwd, full) end
    if fs.isDir(full) then
        for _, name in ipairs(fs.list(full)) do
            if name:sub(1, #base) == base then
                local c = (dir == cwd and "" or (dir .. "/")) .. name
                if fs.isDir(fs.combine(full, name)) then c = c .. "/" end
                out[#out + 1] = c
            end
        end
    end
    return out
end

local ALIASES = {}
local function applyAlias(args)
    if #args == 0 then return args end
    local a = ALIASES[args[1]]
    if not a then return args end
    local expanded = split(a)
    for i = 2, #args do expanded[#expanded + 1] = args[i] end
    return expanded
end

local function readLine(history, cwd)
    local th = theme.get()
    local line = ""
    local cursor = 1
    local hidx = #history + 1
    local sx, sy = term.getCursorPos()
    local function redraw()
        term.setCursorPos(sx, sy)
        term.setTextColor(th.fg); term.setBackgroundColor(th.bg)
        term.write(line .. " ")
        term.setCursorPos(sx + cursor - 1, sy)
    end
    term.setCursorBlink(true)
    redraw()
    while true do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "char" then
            line = line:sub(1, cursor - 1) .. p1 .. line:sub(cursor)
            cursor = cursor + 1; redraw()
        elseif ev == "key" then
            if p1 == keys.enter then
                term.setCursorBlink(false); print("")
                return line
            elseif p1 == keys.backspace and cursor > 1 then
                line = line:sub(1, cursor - 2) .. line:sub(cursor)
                cursor = cursor - 1; redraw()
            elseif p1 == keys.delete then
                line = line:sub(1, cursor - 1) .. line:sub(cursor + 1); redraw()
            elseif p1 == keys.left and cursor > 1 then
                cursor = cursor - 1; redraw()
            elseif p1 == keys.right and cursor <= #line then
                cursor = cursor + 1; redraw()
            elseif p1 == keys.up then
                if hidx > 1 then
                    hidx = hidx - 1; line = history[hidx] or ""; cursor = #line + 1; redraw()
                end
            elseif p1 == keys.down then
                if hidx < #history then
                    hidx = hidx + 1; line = history[hidx] or ""; cursor = #line + 1; redraw()
                else
                    hidx = #history + 1; line = ""; cursor = 1; redraw()
                end
            elseif p1 == keys.tab then
                local parts = split(line)
                local prefix = parts[#parts] or ""
                if #line > 0 and line:sub(-1):match("%s") then prefix = "" end
                local isFirst = (#parts <= 1 and not line:find("%s"))
                local matches
                if isFirst then
                    matches = {}
                    for _, n in ipairs(builtins.list()) do
                        if n:sub(1, #prefix) == prefix then matches[#matches + 1] = n end
                    end
                else
                    matches = completions(prefix, cwd)
                end
                if #matches == 1 then
                    line = line:sub(1, #line - #prefix) .. matches[1]
                    cursor = #line + 1; redraw()
                elseif #matches > 1 then
                    term.setCursorBlink(false); print("")
                    for _, m in ipairs(matches) do io.write(m .. "  ") end
                    print("")
                    sx, sy = term.getCursorPos()
                    redraw()
                end
            elseif p1 == keys.home then cursor = 1; redraw()
            elseif p1 == keys["end"] then cursor = #line + 1; redraw()
            end
        end
    end
end

local function exec(args, ctx)
    args = applyAlias(args)
    if #args == 0 then return 0 end
    local cmd = args[1]
    if cmd == "alias" then
        if #args == 1 then
            for k, v in pairs(ALIASES) do print(k .. "='" .. v .. "'") end
        else
            local eq = table.concat(args, " ", 2):find("=")
            if eq then
                local full = table.concat(args, " ", 2)
                local k = full:sub(1, eq - 1); local v = full:sub(eq + 1)
                if v:sub(1, 1) == "'" or v:sub(1, 1) == '"' then v = v:sub(2, -2) end
                ALIASES[k] = v
            end
        end
        return 0
    end
    if cmd == "exit" or cmd == "quit" then
        ctx.exit = true; return 0
    end
    local fn = builtins.get(cmd)
    if fn then
        local ok, code = pcall(fn, args, ctx)
        if not ok then
            term.setTextColor(theme.get().error); print(tostring(code))
            term.setTextColor(theme.get().fg)
            return 1
        end
        return tonumber(code) or 0
    end
    -- Попытка запустить как файл
    local p = args[1]
    if not p:find("%.lua$") then p = p .. ".lua" end
    if not p:find("^/") then p = fs.combine(ctx.cwd, p) end
    if fs.exists(p) then
        local f, err = loadfile(p, nil, _G)
        if not f then print("Ошибка: " .. err); return 1 end
        local ok, e = pcall(f, table.unpack(args, 2))
        if not ok then
            term.setTextColor(theme.get().error); print(tostring(e))
            term.setTextColor(theme.get().fg); return 1
        end
        return 0
    end
    term.setTextColor(theme.get().error)
    print("Команда не найдена: " .. cmd)
    term.setTextColor(theme.get().fg)
    return 127
end

function M.run(opts)
    opts = opts or {}
    local user = vfs.getUser()
    local ctx = {
        cwd = opts.cwd or user.home or "/",
        user = user.user,
        exit = false,
        history = {},
    }
    local th = theme.get()
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    term.clear(); term.setCursorPos(1, 1)
    print("ЗнатокOS shell. Введите 'help' для справки.")
    while not ctx.exit do
        local th = theme.get()
        term.setTextColor(th.accent); io.write(ctx.user .. "@znatokos")
        term.setTextColor(th.fg);     io.write(":")
        term.setTextColor(colors.lightBlue); io.write(ctx.cwd)
        term.setTextColor(th.fg);     io.write("$ ")
        local line = readLine(ctx.history, ctx.cwd)
        if line and #line > 0 then
            ctx.history[#ctx.history + 1] = line
            if #ctx.history > 100 then table.remove(ctx.history, 1) end
            exec(split(line), ctx)
        end
    end
end

return M
