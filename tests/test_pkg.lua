-- Тестирование pkg: install / list / remove на встроенном каталоге.
local pkg = znatokos.use("pkg/manager")
local T = _G._T

-- Каталог должен содержать встроенные пакеты
local avail = pkg.available()
T.assertTrue(avail.hello ~= nil, "hello in catalog")
T.assertTrue(avail.guess ~= nil, "guess in catalog")

-- Установка
pcall(pkg.remove, "hello")  -- на случай предыдущего прогона
local ok, err = pkg.install("hello")
T.assertTrue(ok, "install hello: " .. tostring(err))
T.assertTrue(fs.exists("/home/hello.lua"), "installed file exists")

-- В списке установленных
local db = pkg.list()
T.assertTrue(db.hello ~= nil, "hello in installed db")
T.assertEq(db.hello.version, "1.0.0", "version recorded")

-- Удаление
local ok2 = pkg.remove("hello")
T.assertTrue(ok2, "remove hello")
T.assertTrue(not fs.exists("/home/hello.lua"), "file removed")
T.assertTrue(pkg.list().hello == nil, "removed from db")

-- Поиск
local results = pkg.search("guess")
T.assertTrue(#results >= 1, "search finds guess")
