-- lib/js.lua
-- Микро-интерпретатор JS-выражений для inline-обработчиков браузера ZnatokOS.
--
-- Это НЕ полный JavaScript. Поддерживается только безопасный whitelist
-- простых выражений, встречающихся в атрибутах onclick/onchange/onsubmit:
--   onclick="navigate('http://example')"
--   onclick="alert('hi'); return false"
--   onclick="location.href='/home'"
--   onclick="history.back()"
--
-- Никакого eval/load() — только pattern matching по регуляркам Lua.
--
-- Поддерживаемые конструкции
-- --------------------------
--   funcName('str')                — вызов функции из ctx
--   funcName("str")                — двойные кавычки
--   funcName('a', 'b')             — несколько строковых аргументов
--   funcName()                     — без аргументов
--   obj.method('arg')              — location/history/console/document.location
--   location = 'url'               — превращается в navigate('url')
--   location.href = 'url'          — то же
--   document.location = 'url'      — то же
--   document.location.href = 'url' — то же
--   history.back() / history.forward()
--   console.log('msg')             — маппится на ctx.alert
--   return false / return          — игнорируется (не ошибка)
--   Несколько statements через ';'
--
-- НЕ поддерживается (тихо игнорируется):
--   var/let/const, if, for, while, арифметика, литералы объектов,
--   this, window, document.* (кроме document.location[.href]),
--   вложенные вызовы в аргументах.
--
-- API:
--   local ok, err = js.eval(code, ctx)
--     ctx = {
--       navigate = function(url) ... end,
--       submit   = function(idOrName) ... end,
--       alert    = function(msg) ... end,
--       back     = function() ... end,
--       forward  = function() ... end,
--     }
--   ok == true  при успешном исполнении (даже если некоторые statements пропущены)
--   ok == false, err при критической ошибке. Ошибки парсинга НЕ кидаются.
--
-- Пример:
--   js.eval("alert('hello'); navigate('/index')", ctx)
--   js.eval("location.href = '/back'", ctx)

local M = {}

-- Ограничения защиты
local MAX_STATEMENTS      = 50
local MAX_STATEMENT_LEN   = 500

-- Безопасная обёртка над ctx-функцией: не падаем, если её нет.
local function call_ctx(ctx, name, ...)
    local fn = ctx and ctx[name]
    if type(fn) == "function" then
        local ok, err = pcall(fn, ...)
        if not ok then
            return false, err
        end
        return true
    end
    -- Функции нет в ctx — это не ошибка, просто игнор.
    return true
end

-- Снять кавычки со строкового литерала: 'x' или "x".
-- Поддержим простые эскейпы \' \" \\ \n \t.
local function strip_string(lit)
    if not lit then return nil end
    lit = lit:match("^%s*(.-)%s*$")
    local inner = lit:match("^'(.*)'$") or lit:match("^\"(.*)\"$")
    if not inner then return nil end
    inner = inner:gsub("\\n", "\n")
                 :gsub("\\t", "\t")
                 :gsub("\\'", "'")
                 :gsub("\\\"", "\"")
                 :gsub("\\\\", "\\")
    return inner
end

-- Разбить строку аргументов по запятым верхнего уровня (учитывая кавычки).
-- Экранирование упрощённое: \' и \" считаем литералом внутри строки.
local function split_args(s)
    local args = {}
    if not s or s:match("^%s*$") then return args end

    local i, n = 1, #s
    local cur = {}
    local in_str = nil -- nil | "'" | '"'
    local prev_bs = false

    while i <= n do
        local c = s:sub(i, i)
        if in_str then
            cur[#cur + 1] = c
            if prev_bs then
                prev_bs = false
            elseif c == "\\" then
                prev_bs = true
            elseif c == in_str then
                in_str = nil
            end
        else
            if c == "'" or c == "\"" then
                in_str = c
                cur[#cur + 1] = c
            elseif c == "," then
                args[#args + 1] = table.concat(cur)
                cur = {}
            else
                cur[#cur + 1] = c
            end
        end
        i = i + 1
    end
    args[#args + 1] = table.concat(cur)

    -- Убрать пустые/пробельные
    local out = {}
    for _, a in ipairs(args) do
        local t = a:match("^%s*(.-)%s*$")
        if t ~= "" then
            out[#out + 1] = t
        end
    end
    return out
end

-- Преобразовать аргумент-выражение в значение Lua.
-- Поддерживаем: строковые литералы, числа, true/false/null/undefined,
-- идентификаторы из ctx (если есть).
local function eval_arg(raw, ctx)
    if not raw then return nil end
    raw = raw:match("^%s*(.-)%s*$")
    if raw == "" then return nil end

    -- Строка?
    local s = strip_string(raw)
    if s ~= nil then return s end

    -- Число?
    local num = tonumber(raw)
    if num ~= nil then return num end

    -- Литералы
    if raw == "true"      then return true end
    if raw == "false"     then return false end
    if raw == "null"      then return nil end
    if raw == "undefined" then return nil end

    -- Идентификатор из ctx (например, имя формы в submit(formName))
    if raw:match("^[%w_]+$") then
        if ctx and ctx[raw] ~= nil then return ctx[raw] end
        -- Иначе возвращаем как строку — частый кейс submit(myform)
        return raw
    end

    -- Прочее — отдадим сырую строку как есть (без кавычек).
    return raw
end

-- Обработка одного statement. Возвращает true/false, err.
local function exec_statement(stmt, ctx)
    stmt = stmt:match("^%s*(.-)%s*$")
    if stmt == "" then return true end
    if #stmt > MAX_STATEMENT_LEN then
        return false, "statement too long"
    end

    -- return / return false / return true — игнорируем
    if stmt:match("^return%s*;?$")
        or stmt:match("^return%s+[%w_'\"]+%s*;?$") then
        return true
    end

    -- Срезать хвостовую точку с запятой, если есть
    stmt = stmt:gsub(";%s*$", "")

    -- 1) Присваивания location / document.location (вариации с .href).
    local rhs = stmt:match("^location%s*=%s*(.+)$")
               or stmt:match("^location%.href%s*=%s*(.+)$")
               or stmt:match("^document%.location%s*=%s*(.+)$")
               or stmt:match("^document%.location%.href%s*=%s*(.+)$")
               or stmt:match("^window%.location%s*=%s*(.+)$")
               or stmt:match("^window%.location%.href%s*=%s*(.+)$")
    if rhs then
        local url = eval_arg(rhs, ctx)
        if type(url) == "string" then
            return call_ctx(ctx, "navigate", url)
        end
        return true -- молча игнорируем нестроковый rhs
    end

    -- 2) Вызов: ident(args) либо obj.method(args)
    local callee, args_src = stmt:match("^([%w_%.]+)%s*%((.-)%)%s*$")
    if callee then
        local args_list = split_args(args_src)
        local args = {}
        for i, a in ipairs(args_list) do
            args[i] = eval_arg(a, ctx)
        end

        -- Диспетчер по имени
        if callee == "navigate" then
            return call_ctx(ctx, "navigate", args[1])
        elseif callee == "submit" then
            return call_ctx(ctx, "submit", args[1])
        elseif callee == "alert" then
            return call_ctx(ctx, "alert", args[1])
        elseif callee == "back" then
            return call_ctx(ctx, "back")
        elseif callee == "forward" then
            return call_ctx(ctx, "forward")
        elseif callee == "history.back" then
            return call_ctx(ctx, "back")
        elseif callee == "history.forward" then
            return call_ctx(ctx, "forward")
        elseif callee == "history.go" then
            -- history.go(-1) → back, history.go(1) → forward
            local n = tonumber(args[1])
            if n and n < 0 then return call_ctx(ctx, "back")
            elseif n and n > 0 then return call_ctx(ctx, "forward") end
            return true
        elseif callee == "console.log"
            or callee == "console.info"
            or callee == "console.warn"
            or callee == "console.error" then
            local msg = args[1]
            if msg == nil then msg = "" end
            return call_ctx(ctx, "alert", tostring(msg))
        elseif callee == "window.close" then
            return call_ctx(ctx, "back")
        else
            -- Универсальный fallback: если ctx знает такую функцию — зовём.
            if ctx and type(ctx[callee]) == "function" then
                return call_ctx(ctx, callee, table.unpack and table.unpack(args) or unpack(args))
            end
            -- Неизвестная функция — тихо игнорируем.
            return true
        end
    end

    -- 3) void(0), true/false, голый идентификатор, пустота — игнор.
    if stmt:match("^void%s*%(.*%)$") then return true end
    if stmt == "true" or stmt == "false" or stmt == "null" or stmt == "undefined" then
        return true
    end
    if stmt:match("^[%w_%.]+$") then
        return true
    end

    -- Неопознанный statement — не ошибка, но вернём предупреждение.
    return true
end

-- Разбить код по ';' верхнего уровня (учитывая кавычки).
local function split_statements(code)
    local out = {}
    local buf = {}
    local i, n = 1, #code
    local in_str = nil
    local prev_bs = false

    while i <= n do
        local c = code:sub(i, i)
        if in_str then
            buf[#buf + 1] = c
            if prev_bs then
                prev_bs = false
            elseif c == "\\" then
                prev_bs = true
            elseif c == in_str then
                in_str = nil
            end
        else
            if c == "'" or c == "\"" then
                in_str = c
                buf[#buf + 1] = c
            elseif c == ";" then
                out[#out + 1] = table.concat(buf)
                buf = {}
            else
                buf[#buf + 1] = c
            end
        end
        i = i + 1
        if #out > MAX_STATEMENTS then break end
    end
    out[#out + 1] = table.concat(buf)
    return out
end

-- Публичный API: выполнить строку кода.
function M.eval(code, ctx)
    if type(code) ~= "string" then
        return false, "code must be a string"
    end
    ctx = ctx or {}

    -- Всё в pcall — гарантируем, что не кинем ошибку наружу.
    local ok, err = pcall(function()
        local stmts = split_statements(code)
        if #stmts > MAX_STATEMENTS then
            -- Обрежем до лимита.
            for i = #stmts, MAX_STATEMENTS + 1, -1 do
                stmts[i] = nil
            end
        end
        for _, s in ipairs(stmts) do
            exec_statement(s, ctx)
        end
    end)

    if not ok then
        return false, tostring(err)
    end
    return true, nil
end

return M
