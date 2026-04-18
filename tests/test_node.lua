-- Тесты идентичности узла (kernel/node).
-- Подменяем paths.ETC на временную директорию, чтобы не трогать рабочий конфиг.
local T = _G._T
local paths = znatokos.use("fs/paths")
local node  = znatokos.use("kernel/node")

-- Готовим песочницу.
local TMP_ETC = "/tmp/test-node"
if fs.exists(TMP_ETC) then fs.delete(TMP_ETC) end
fs.makeDir(TMP_ETC)

local origEtc = paths.ETC
paths.ETC = TMP_ETC

-- Сбрасываем состояние модуля, чтобы load() отработал с чистого листа.
-- Модуль закрыт, но load() сам перезапишет state при повторном вызове —
-- достаточно убедиться, что файла конфига в TMP_ETC нет.
local cfgFile = TMP_ETC .. "/node.cfg"
if fs.exists(cfgFile) then fs.delete(cfgFile) end

-- 1) Первый load: генерирует id и создаёт файл.
local first = node.load()
T.assertTrue(first ~= nil, "node.load() returns table")
T.assertTrue(type(first.id) == "string", "id is string")
T.assertTrue(first.id:sub(1, 7) == "znatok-", "id has znatok- prefix")
T.assertEq(#first.id, 7 + 16, "id length = prefix + 16 hex")
T.assertEq(first.role, "workstation", "default role is workstation")
T.assertTrue(fs.exists(cfgFile), "node.cfg создан на диске")

local firstId = first.id

-- 2) Повторный load читает тот же id (не перегенерит).
local second = node.load()
T.assertEq(second.id, firstId, "повторный load возвращает тот же id")
T.assertEq(node.getId(), firstId, "getId совпадает")

-- 3) setName: валидация длины и символов.
local ok, err = node.setName("")
T.assertTrue(not ok, "пустое имя отклонено")
ok, err = node.setName(string.rep("a", 33))
T.assertTrue(not ok, "имя > 32 отклонено")
ok, err = node.setName("bad name!")      -- пробел и !
T.assertTrue(not ok, "имя с недопустимыми символами отклонено")
ok, err = node.setName("плохое")          -- кириллица = многобайтовые
T.assertTrue(not ok, "кириллица (по байтам) отклонена текущим паттерном")
ok, err = node.setName("good-name_1.x")
T.assertTrue(ok, "валидное имя принято: " .. tostring(err))
T.assertEq(node.getName(), "good-name_1.x", "имя обновлено")

-- 4) setRole: валидация.
ok, err = node.setRole("overlord")
T.assertTrue(not ok, "невалидная роль отклонена")
T.assertEq(node.getRole(), "workstation", "роль не поменялась")
ok, err = node.setRole("server")
T.assertTrue(ok, "роль server принята: " .. tostring(err))
T.assertEq(node.getRole(), "server", "роль обновлена")

-- 5) Сохранение переживает повторный load: читаем файл заново через loadfile.
local fn = assert(loadfile(cfgFile, nil, _G))
local data = fn()
T.assertEq(data.id, firstId, "сохранённый id совпадает")
T.assertEq(data.name, "good-name_1.x", "сохранённое имя совпадает")
T.assertEq(data.role, "server", "сохранённая роль совпадает")

-- Возвращаем paths.ETC обратно и убираем за собой.
paths.ETC = origEtc
if fs.exists(TMP_ETC) then fs.delete(TMP_ETC) end
