-- Тесты парсера и валидатора manifest.lua.
local manifest = znatokos.use("pkg/manifest")
local T = _G._T

-- Готовим временный корректный manifest для теста load().
local TMP_DIR = "/znatokos/var/tmp/manifest_test"
local TMP_OK = TMP_DIR .. "/manifest.lua"
if not fs.exists(TMP_DIR) then fs.makeDir(TMP_DIR) end
do
    local f = fs.open(TMP_OK, "w")
    f.write([[
return {
    id = "com.znatok.demo",
    name = "Демо",
    version = "1.2.3",
    author = "znatok",
    description = "Демонстрационное приложение",
    entry = "main.lua",
    files = { "main.lua", "lib/util.lua" },
    capabilities = { "ui.window", "fs.home" },
}
]])
    f.close()
end

-- load() корректного манифеста
local m, err = manifest.load(TMP_OK)
T.assertTrue(m ~= nil, "load ok: " .. tostring(err))
T.assertEq(m and m.id, "com.znatok.demo", "load: id прочитан")
T.assertEq(m and m.version, "1.2.3", "load: version прочитан")

-- validate() корректного манифеста
local ok, verr = manifest.validate(m)
T.assertTrue(ok, "validate ok: " .. tostring(verr))

-- validate: отсутствует id
local bad = { name = "X", version = "1.0.0", entry = "m.lua", files = { "m.lua" } }
local ok1, err1 = manifest.validate(bad)
T.assertEq(ok1, false, "validate: отклоняет без id")
T.assertTrue(err1 and err1:find("id") ~= nil, "validate: сообщение про id")

-- validate: id не по regex
local bad2 = { id = "ABC Wrong!", name = "X", version = "1.0.0", entry = "m.lua", files = { "m.lua" } }
local ok2 = manifest.validate(bad2)
T.assertEq(ok2, false, "validate: отклоняет невалидный id")

-- validate: невалидная capability
local bad3 = {
    id = "com.x.y", name = "X", version = "1.0.0",
    entry = "m.lua", files = { "m.lua" },
    capabilities = { "ui.window", "not.a.real.cap" },
}
local ok3, err3 = manifest.validate(bad3)
T.assertEq(ok3, false, "validate: отклоняет невалидную capability")
T.assertTrue(err3 and err3:find("not.a.real.cap", 1, true) ~= nil, "validate: сообщение про cap")

-- validate: path traversal в files
local bad4 = {
    id = "com.x.y", name = "X", version = "1.0.0",
    entry = "m.lua", files = { "m.lua", "../evil.lua" },
}
local ok4 = manifest.validate(bad4)
T.assertEq(ok4, false, "validate: отклоняет .. в files")

-- validate: абсолютный путь в files
local bad4b = {
    id = "com.x.y", name = "X", version = "1.0.0",
    entry = "m.lua", files = { "m.lua", "/absolute.lua" },
}
local ok4b = manifest.validate(bad4b)
T.assertEq(ok4b, false, "validate: отклоняет абсолютный путь")

-- validate: entry не содержится в files
local bad5 = {
    id = "com.x.y", name = "X", version = "1.0.0",
    entry = "main.lua", files = { "other.lua" },
}
local ok5, err5 = manifest.validate(bad5)
T.assertEq(ok5, false, "validate: entry должен быть в files")
T.assertTrue(err5 and err5:find("files", 1, true) ~= nil, "validate: сообщение про files")

-- validate: невалидная semver
local bad6 = {
    id = "com.x.y", name = "X", version = "1.0",
    entry = "m.lua", files = { "m.lua" },
}
local ok6 = manifest.validate(bad6)
T.assertEq(ok6, false, "validate: отклоняет невалидную semver")

-- versionCompare
T.assertEq(manifest.versionCompare("1.0.0", "1.0.0"), 0, "versionCompare: равные")
T.assertEq(manifest.versionCompare("1.0.0", "1.0.1"), -1, "versionCompare: patch меньше")
T.assertEq(manifest.versionCompare("1.1.0", "1.0.9"), 1, "versionCompare: minor больше")
T.assertEq(manifest.versionCompare("2.0.0", "1.99.99"), 1, "versionCompare: major больше")
T.assertEq(manifest.versionCompare("0.3.0", "1.0.0"), -1, "versionCompare: major меньше")

-- versionMatches: точное
T.assertEq(manifest.versionMatches("1.2.3", "1.2.3"), true, "match: точное совпадение")
T.assertEq(manifest.versionMatches("1.2.4", "1.2.3"), false, "match: точное не совпадает")

-- >=, >, <=, <
T.assertEq(manifest.versionMatches("1.2.3", ">=1.2.3"), true, "match: >= равно")
T.assertEq(manifest.versionMatches("1.2.4", ">=1.2.3"), true, "match: >= больше")
T.assertEq(manifest.versionMatches("1.2.2", ">=1.2.3"), false, "match: >= меньше")
T.assertEq(manifest.versionMatches("1.2.3", ">1.2.3"), false, "match: > равно")
T.assertEq(manifest.versionMatches("1.2.4", ">1.2.3"), true, "match: > больше")
T.assertEq(manifest.versionMatches("1.2.3", "<=1.2.3"), true, "match: <= равно")
T.assertEq(manifest.versionMatches("1.2.2", "<=1.2.3"), true, "match: <= меньше")
T.assertEq(manifest.versionMatches("1.2.3", "<1.2.3"), false, "match: < равно")
T.assertEq(manifest.versionMatches("1.2.2", "<1.2.3"), true, "match: < меньше")

-- caret ^: тот же major
T.assertEq(manifest.versionMatches("1.2.3", "^1.2.3"), true, "match: ^ равно")
T.assertEq(manifest.versionMatches("1.5.0", "^1.2.3"), true, "match: ^ больше по minor")
T.assertEq(manifest.versionMatches("1.2.2", "^1.2.3"), false, "match: ^ меньше")
T.assertEq(manifest.versionMatches("2.0.0", "^1.2.3"), false, "match: ^ другой major")

-- tilde ~: тот же major.minor
T.assertEq(manifest.versionMatches("1.2.3", "~1.2.3"), true, "match: ~ равно")
T.assertEq(manifest.versionMatches("1.2.9", "~1.2.3"), true, "match: ~ больше по patch")
T.assertEq(manifest.versionMatches("1.3.0", "~1.2.3"), false, "match: ~ другой minor")
T.assertEq(manifest.versionMatches("1.2.2", "~1.2.3"), false, "match: ~ меньше")

-- Уборка
pcall(fs.delete, TMP_DIR)
