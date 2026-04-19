-- tests/test_url.lua
-- Тесты для lib/url.lua.
-- Запуск (вне ZnatokOS):  lua test_url.lua
-- Запуск внутри ZnatokOS: /znatokos/apps/com.znatok.browser/tests/test_url.lua
--
-- Скрипт пытается загрузить модуль через require, а если не выходит —
-- через dofile относительно собственного пути. Это даёт шанс работать
-- и в чистом Lua, и в CC:Tweaked.

-- Попробуем настроить package.path, чтобы найти соседнюю lib/
local function addPath()
    local sep = package.config:sub(1, 1)
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    -- Убираем имя файла -> каталог tests
    local dir = src:match("(.*" .. sep .. ")") or ("." .. sep)
    -- Добавляем ../lib/?.lua
    local libPath = dir .. ".." .. sep .. "lib" .. sep .. "?.lua"
    package.path = libPath .. ";" .. package.path
end

pcall(addPath)

local ok, url = pcall(require, "url")
if not ok then
    error("Не удалось загрузить модуль url: " .. tostring(url))
end

------------------------------------------------------------
-- Мини-фреймворк тестов
------------------------------------------------------------
local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: ожидалось %q, получено %q",
            msg or "assertEq",
            tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(cond, msg)
    if not cond then error(msg or "assertTrue failed", 2) end
end

local function assertNil(v, msg)
    if v ~= nil then
        error((msg or "assertNil failed") .. " (got " .. tostring(v) .. ")", 2)
    end
end

------------------------------------------------------------
-- Тесты parse
------------------------------------------------------------
test("parse: http без пути", function()
    local p, err = url.parse("http://example.com/")
    assertTrue(p, "parse должен вернуть таблицу, err=" .. tostring(err))
    assertEq(p.scheme, "http")
    assertEq(p.host, "example.com")
    assertEq(p.port, 80)
    assertEq(p.path, "/")
    assertEq(p.query, "")
    assertEq(p.fragment, "")
end)

test("parse: https с путём", function()
    local p = assert(url.parse("https://github.com/user/repo"))
    assertEq(p.scheme, "https")
    assertEq(p.host, "github.com")
    assertEq(p.port, 443)
    assertEq(p.path, "/user/repo")
end)

test("parse: с портом, query и fragment", function()
    local p = assert(url.parse("http://host:8080/path?q=1#f"))
    assertEq(p.port, 8080)
    assertEq(p.path, "/path")
    assertEq(p.query, "?q=1")
    assertEq(p.fragment, "#f")
end)

test("parse: ftp -> ошибка", function()
    local p, err = url.parse("ftp://example.com/x")
    assertNil(p, "ftp не должен парситься")
    assertTrue(err, "должна быть ошибка")
end)

test("parse: not a url -> ошибка", function()
    local p, err = url.parse("not a url")
    assertNil(p)
    assertTrue(err)
end)

test("parse: пустая строка -> ошибка", function()
    local p, err = url.parse("")
    assertNil(p)
    assertTrue(err)
end)

test("parse: host lowercased", function()
    local p = assert(url.parse("HTTP://EXAMPLE.COM/Path"))
    assertEq(p.scheme, "http")
    assertEq(p.host, "example.com")
    assertEq(p.path, "/Path") -- путь НЕ трогаем
end)

------------------------------------------------------------
-- Тесты build
------------------------------------------------------------
test("build: симметричен parse для простого URL", function()
    local parts = {
        scheme = "https", host = "example.com", port = 443,
        path = "/a/b", query = "?x=1", fragment = "#z",
    }
    local s = url.build(parts)
    assertEq(s, "https://example.com/a/b?x=1#z")
end)

test("build: нестандартный порт включается", function()
    local s = url.build({
        scheme = "http", host = "h", port = 8080, path = "/"
    })
    assertEq(s, "http://h:8080/")
end)

------------------------------------------------------------
-- Тесты resolve
------------------------------------------------------------
test("resolve: абсолютный путь", function()
    assertEq(url.resolve("http://a.com/b/c", "/d"), "http://a.com/d")
end)

test("resolve: относительный путь", function()
    assertEq(url.resolve("http://a.com/b/c", "d"), "http://a.com/b/d")
end)

test("resolve: абсолютный URL не меняется", function()
    assertEq(url.resolve("http://a.com/b/c", "https://x.com/y"),
        "https://x.com/y")
end)

test("resolve: schema-relative //", function()
    assertEq(url.resolve("https://a.com/x", "//b.com/y"),
        "https://b.com/y")
end)

test("resolve: относительный с концевым слэшем в base", function()
    assertEq(url.resolve("http://a.com/b/", "c"), "http://a.com/b/c")
end)

test("resolve: query-only", function()
    assertEq(url.resolve("http://a.com/p", "?x=1"), "http://a.com/p?x=1")
end)

------------------------------------------------------------
-- Тесты isUrl
------------------------------------------------------------
test("isUrl: http URL", function()
    assertTrue(url.isUrl("http://a.com"))
    assertTrue(url.isUrl("https://a.com/x"))
end)

test("isUrl: произвольная строка", function()
    assertEq(url.isUrl("hello"), false)
    assertEq(url.isUrl(""), false)
end)

------------------------------------------------------------
-- Тесты encode/decode
------------------------------------------------------------
test("decode: %20 -> пробел", function()
    assertEq(url.decode("hello%20world"), "hello world")
end)

test("encode/decode round-trip", function()
    local s = "hello world & friends"
    assertEq(url.decode(url.encode(s)), s)
end)

------------------------------------------------------------
-- Тесты queryParse / queryBuild
------------------------------------------------------------
test("queryParse: простой случай", function()
    local t = url.queryParse("?x=1&y=hello%20world")
    assertEq(t.x, "1")
    assertEq(t.y, "hello world")
end)

test("queryParse: без ведущего ?", function()
    local t = url.queryParse("a=1&b=2")
    assertEq(t.a, "1")
    assertEq(t.b, "2")
end)

test("queryParse: пустая строка", function()
    local t = url.queryParse("")
    -- Таблица должна быть пустой
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    assertEq(count, 0)
end)

test("queryBuild: кодирует пробелы", function()
    local s = url.queryBuild({ x = "a b", y = "c" })
    -- Порядок детерминирован (sorted): x сперва
    -- encode("a b") = "a%20b" либо "a+b" в зависимости от реализации
    -- Допускаем оба варианта
    assertTrue(s == "?x=a%20b&y=c" or s == "?x=a+b&y=c",
        "неожиданный queryBuild результат: " .. s)
end)

test("queryBuild: пустая таблица -> пустая строка", function()
    assertEq(url.queryBuild({}), "")
end)

test("queryParse/queryBuild round-trip", function()
    local original = { foo = "bar baz", n = "42" }
    local s = url.queryBuild(original)
    local parsed = url.queryParse(s)
    assertEq(parsed.foo, "bar baz")
    assertEq(parsed.n, "42")
end)

------------------------------------------------------------
-- Запуск тестов
------------------------------------------------------------
local passed, failed = 0, 0
local failures = {}

for _, t in ipairs(tests) do
    local ok2, err = pcall(t.fn)
    if ok2 then
        passed = passed + 1
        print("[OK]   " .. t.name)
    else
        failed = failed + 1
        failures[#failures + 1] = { t.name, err }
        print("[FAIL] " .. t.name .. ": " .. tostring(err))
    end
end

print(string.format("\nИтого: %d прошло, %d упало (из %d)",
    passed, failed, #tests))

if failed > 0 then
    -- Неуспешный exit-код для автоматизации
    if os and os.exit then os.exit(1) end
end
