-- Ручной ранер тестов для ЗнатокOS.
-- Запуск в CC: Tweaked:  run /znatokos/tests/run_tests.lua
if not _G.znatokos then
    -- Если запускаемся без загруженной ОС — инициализируем минимум.
    _G.znatokos = { VERSION = "test", loaded = {} }
    function _G.znatokos.use(path)
        if _G.znatokos.loaded[path] then return _G.znatokos.loaded[path] end
        local fn = assert(loadfile("/znatokos/src/" .. path .. ".lua", nil, _G))
        local m = fn(); _G.znatokos.loaded[path] = m; return m
    end
end

local T = { pass = 0, fail = 0, failures = {} }
function T.assertEq(a, b, name)
    if a == b then T.pass = T.pass + 1
    else T.fail = T.fail + 1; T.failures[#T.failures + 1] = name .. ": got " .. tostring(a) .. " expected " .. tostring(b) end
end
function T.assertTrue(x, name)
    if x then T.pass = T.pass + 1
    else T.fail = T.fail + 1; T.failures[#T.failures + 1] = name .. ": expected truthy, got " .. tostring(x) end
end
function T.section(name)
    print("")
    term.setTextColor(colors.yellow); print("== " .. name .. " ==")
    term.setTextColor(colors.white)
end
_G._T = T

local suites = { "test_shell", "test_sha256", "test_vfs", "test_pkg" }
for _, s in ipairs(suites) do
    T.section(s)
    local ok, err = pcall(function()
        local fn = assert(loadfile("/znatokos/tests/" .. s .. ".lua", nil, _G))
        fn()
    end)
    if not ok then
        T.fail = T.fail + 1
        T.failures[#T.failures + 1] = s .. " crashed: " .. tostring(err)
    end
end

print("")
term.setTextColor(T.fail == 0 and colors.lime or colors.red)
print(("Итого: %d PASS, %d FAIL"):format(T.pass, T.fail))
term.setTextColor(colors.white)
for _, f in ipairs(T.failures) do print("  ! " .. f) end
