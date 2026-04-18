-- Тесты песочницы: permissions persistence + построение _ENV.
local sandbox = znatokos.use("pkg/sandbox")
local T = _G._T

-- Изолируем тесты: подменяем путь БД на временный
local TMP_DB = "/znatokos/var/tmp/permissions_test.db"
pcall(fs.delete, TMP_DB)
local origPath = sandbox._getDBPath()
sandbox._setDBPath(TMP_DB)

-- ---------------------------------------------------------------
-- 1. permissionsGrant / permissionsGet: базовые + persistence
-- ---------------------------------------------------------------
sandbox.permissionsClear("com.znatok.browser")
sandbox.permissionsClear("com.znatok.editor")

local okGrant, errGrant = sandbox.permissionsGrant("com.znatok.browser", "ui.window", true)
T.assertTrue(okGrant, "grant ui.window: " .. tostring(errGrant))

local p = sandbox.permissionsGet("com.znatok.browser")
T.assertEq(p["ui.window"], true, "get возвращает granted")

-- Валидация: несуществующая capability отклоняется
local bad, badErr = sandbox.permissionsGrant("com.znatok.browser", "no.such.cap", true)
T.assertEq(bad, false, "неизвестная cap отклонена")
T.assertTrue(badErr ~= nil, "есть текст ошибки")

-- Разные apps независимы
sandbox.permissionsGrant("com.znatok.editor", "fs.home", true)
local pBrowser = sandbox.permissionsGet("com.znatok.browser")
local pEditor  = sandbox.permissionsGet("com.znatok.editor")
T.assertTrue(pBrowser["fs.home"] == nil, "editor's cap не попал в browser")
T.assertEq(pEditor["fs.home"], true, "editor имеет fs.home")

-- Persist: проверим что файл БД реально создан и читается заново.
T.assertTrue(fs.exists(TMP_DB), "файл БД создан")

-- "Перезагрузка": получить через новый вызов — читает с диска
sandbox.permissionsGrant("com.znatok.browser", "net.http", true)
local reload = sandbox.permissionsGet("com.znatok.browser")
T.assertEq(reload["net.http"], true, "net.http persisted")
T.assertEq(reload["ui.window"], true, "ui.window всё ещё там")

-- ---------------------------------------------------------------
-- 2. permissionsHas: true только при явном true
-- ---------------------------------------------------------------
sandbox.permissionsGrant("com.znatok.browser", "fs.home", false)
T.assertEq(sandbox.permissionsHas("com.znatok.browser", "ui.window"), true, "has true")
T.assertEq(sandbox.permissionsHas("com.znatok.browser", "fs.home"), false, "has с явным false = false")
T.assertEq(sandbox.permissionsHas("com.znatok.browser", "fs.all"), false, "has без записи = false")

-- ---------------------------------------------------------------
-- 3. permissionsMissing: запрошено, не granted, НЕ включает явный false
-- ---------------------------------------------------------------
local missing = sandbox.permissionsMissing(
    "com.znatok.browser",
    { "ui.window", "net.http", "fs.home", "periph.list" }
)
-- ui.window = true => не missing
-- net.http  = true => не missing
-- fs.home   = false => решено (не missing)
-- periph.list = нет записи => missing
T.assertEq(#missing, 1, "missing содержит только periph.list")
T.assertEq(missing[1], "periph.list", "missing[1] == periph.list")

-- ---------------------------------------------------------------
-- 4. permissionsUnknown: только полностью без записи
-- ---------------------------------------------------------------
local unknown = sandbox.permissionsUnknown(
    "com.znatok.browser",
    { "ui.window", "net.http", "fs.home", "periph.list", "net.rednet" }
)
-- unknown = те, где записи НЕТ совсем: periph.list, net.rednet
T.assertEq(#unknown, 2, "unknown содержит 2")
local set = {}; for _, v in ipairs(unknown) do set[v] = true end
T.assertTrue(set["periph.list"], "periph.list unknown")
T.assertTrue(set["net.rednet"], "net.rednet unknown")

-- ---------------------------------------------------------------
-- 5. build: без net.http — env.http == nil; с net.http — проброшено
-- ---------------------------------------------------------------
local user = { user = "testuser", home = "/home/testuser" }

local envNoHttp = sandbox.build({
    appId = "x.test", user = user, caps = { "ui.window" }, appDir = "/tmp/x",
})
T.assertEq(envNoHttp.http, nil, "без net.http -> http nil")

local envHttp = sandbox.build({
    appId = "x.test", user = user, caps = { "net.http" }, appDir = "/tmp/x",
})
T.assertTrue(envHttp.http ~= nil, "с net.http -> http присутствует")
T.assertTrue(rawequal(envHttp.http, http), "env.http == real http")

-- ---------------------------------------------------------------
-- 6. build: без fs.all и без fs.home — env.fs == nil
-- ---------------------------------------------------------------
local envNoFs = sandbox.build({
    appId = "x.test", user = user, caps = { "ui.window" }, appDir = "/tmp/x",
})
T.assertEq(envNoFs.fs, nil, "без fs.* env.fs == nil")

local envAll = sandbox.build({
    appId = "x.test", user = user, caps = { "fs.all" }, appDir = "/tmp/x",
})
T.assertTrue(rawequal(envAll.fs, fs), "fs.all -> real fs")
T.assertEq(sandbox.allowRoot({ "fs.all" }), true, "allowRoot true для fs.all")
T.assertEq(sandbox.allowRoot({ "fs.home" }), false, "allowRoot false для fs.home")

-- ---------------------------------------------------------------
-- 7. fs.home: доступ ограничен home-директорией
-- ---------------------------------------------------------------
local HOME = "/home/testuser_sandbox"
pcall(fs.delete, HOME)
fs.makeDir(HOME)

local envHome = sandbox.build({
    appId  = "x.test",
    user   = { user = "testuser_sandbox", home = HOME },
    caps   = { "fs.home" },
    appDir = "/tmp/x",
})
T.assertTrue(envHome.fs ~= nil, "fs.home -> есть env.fs")
T.assertTrue(not rawequal(envHome.fs, fs), "env.fs не реальный fs (прокси)")

-- Запись внутри home должна работать
local okFile = HOME .. "/file.txt"
local h, openErr = envHome.fs.open(okFile, "w")
T.assertTrue(h ~= nil, "open файла внутри home: " .. tostring(openErr))
if h then h.write("hello"); h.close() end
T.assertEq(envHome.fs.exists(okFile), true, "exists true для home-файла")

-- Относительный путь должен резолвиться внутрь home
local h2 = envHome.fs.open("rel.txt", "w")
T.assertTrue(h2 ~= nil, "относительный путь резолвится в home")
if h2 then h2.write("x"); h2.close() end
T.assertEq(fs.exists(HOME .. "/rel.txt"), true, "реальный файл создан в home")

-- Запись в системный путь должна быть отклонена
local hDeny, denyErr = envHome.fs.open("/znatokos/etc/passwd_hack", "w")
T.assertEq(hDeny, nil, "open /znatokos/etc отклонён")
T.assertTrue(denyErr ~= nil, "есть текст ошибки")

-- Попытка вырваться через ..
local hEscape, escErr = envHome.fs.open("../../znatokos/etc/pwd", "w")
T.assertEq(hEscape, nil, "путь с .. отклонён")
T.assertTrue(escErr ~= nil, "есть текст ошибки про ..")

-- delete вне home должно бросать ошибку
local okDel = pcall(envHome.fs.delete, "/znatokos/etc/passwd")
T.assertEq(okDel, false, "delete вне home бросает")

-- Чистим за собой
pcall(fs.delete, HOME)

-- ---------------------------------------------------------------
-- 8. permissionsClear удаляет запись
-- ---------------------------------------------------------------
sandbox.permissionsGrant("com.znatok.tmp", "ui.window", true)
T.assertEq(sandbox.permissionsHas("com.znatok.tmp", "ui.window"), true, "granted before clear")
sandbox.permissionsClear("com.znatok.tmp")
local cleared = sandbox.permissionsGet("com.znatok.tmp")
T.assertEq(next(cleared), nil, "после clear запись пустая")
T.assertEq(sandbox.permissionsHas("com.znatok.tmp", "ui.window"), false, "has false после clear")

-- ---------------------------------------------------------------
-- Финализация: убираем временную БД, восстанавливаем путь
-- ---------------------------------------------------------------
pcall(fs.delete, TMP_DB)
sandbox._setDBPath(origPath)
