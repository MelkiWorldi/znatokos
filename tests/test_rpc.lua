-- Проверка RPC-слоя: регистрация методов, фреймы, встроенные handlers.
-- Реальные rednet-вызовы не симулируем (нет mock-модема).
local T = _G._T
local rpc = znatokos.use("net/rpc")

--------------------------------------------------------------
-- 1. register / listMethods / unregister
--------------------------------------------------------------

-- Встроенные методы должны быть зарегистрированы сразу после require.
local initial = rpc.listMethods()
local function has(list, name)
    for _, v in ipairs(list) do if v == name then return true end end
    return false
end
T.assertTrue(has(initial, "ping"),  "ping зарегистрирован по умолчанию")
T.assertTrue(has(initial, "echo"),  "echo зарегистрирован по умолчанию")
T.assertTrue(has(initial, "info"),  "info зарегистрирован по умолчанию")

-- Добавляем новый метод.
rpc.register("test.sum", function(args)
    return (args[1] or 0) + (args[2] or 0)
end)
T.assertTrue(has(rpc.listMethods(), "test.sum"), "register добавил метод")

-- Удаление.
rpc.unregister("test.sum")
T.assertTrue(not has(rpc.listMethods(), "test.sum"), "unregister удалил метод")

-- register валидирует аргументы.
local ok1 = pcall(rpc.register, "", function() end)
T.assertEq(ok1, false, "пустое имя метода отклонено")
local ok2 = pcall(rpc.register, "x", "not a function")
T.assertEq(ok2, false, "не-функция отклонена")

--------------------------------------------------------------
-- 2. encodeFrame / decodeFrame — круговой trip
--------------------------------------------------------------

local callFr = rpc.encodeFrame("call", "nonce-1",
    { method = "ping", args = { 1, 2 } })
T.assertEq(callFr.proto,  "znatokos.rpc", "encode: proto")
T.assertEq(callFr.kind,   "call",         "encode: kind")
T.assertEq(callFr.id,     "nonce-1",      "encode: id")
T.assertEq(callFr.method, "ping",         "encode: method")

-- Круговой trip через сериализацию (эмулирует передачу по сети).
local serialized = textutils.serialize(callFr)
local restored   = textutils.unserialize(serialized)
local fr, err = rpc.decodeFrame(restored)
T.assertTrue(fr ~= nil, "decode вернул фрейм: " .. tostring(err))
T.assertEq(fr.method, "ping", "decode: method сохранён")
T.assertEq(fr.args[2], 2,     "decode: args сохранены")

-- Reply-фрейм с табличным result.
local replyFr = rpc.encodeFrame("reply", "nonce-1", {
    result = { a = 1, b = { "x", "y" } },
})
local replyBack = textutils.unserialize(textutils.serialize(replyFr))
local rr = rpc.decodeFrame(replyBack)
T.assertTrue(rr ~= nil, "decode reply")
T.assertEq(rr.result.a, 1, "reply: result.a")
T.assertEq(rr.result.b[2], "y", "reply: result.b[2]")

-- Error-фрейм.
local errFr = rpc.encodeFrame("error", "nonce-1", { error = "boom" })
local eb = rpc.decodeFrame(textutils.unserialize(textutils.serialize(errFr)))
T.assertEq(eb.kind, "error", "error kind")
T.assertEq(eb.error, "boom", "error message")

-- Невалидные фреймы.
local _, e1 = rpc.decodeFrame(nil)
T.assertTrue(e1 ~= nil, "nil фрейм отклонён")
local _, e2 = rpc.decodeFrame({ proto = "other", kind = "call", id = "x" })
T.assertTrue(e2 ~= nil, "чужой proto отклонён")
local _, e3 = rpc.decodeFrame({ proto = "znatokos.rpc", kind = "junk", id = "x" })
T.assertTrue(e3 ~= nil, "неизвестный kind отклонён")
local _, e4 = rpc.decodeFrame({ proto = "znatokos.rpc", kind = "call" })
T.assertTrue(e4 ~= nil, "без id отклонён")
local _, e5 = rpc.decodeFrame({ proto = "znatokos.rpc", kind = "call", id = "x" })
T.assertTrue(e5 ~= nil, "call без method отклонён")

-- encodeFrame тоже валидирует.
local okEnc = pcall(rpc.encodeFrame, "weird", "x", {})
T.assertEq(okEnc, false, "encode отклонил неизвестный kind")

--------------------------------------------------------------
-- 3. Handlers встроенных методов
--------------------------------------------------------------

local pingH = rpc._getHandler("ping")
T.assertEq(pingH({}), "pong", "ping возвращает pong")

local echoH = rpc._getHandler("echo")
local echoed = echoH({ "hello", "world" })
T.assertEq(type(echoed), "table",  "echo вернул таблицу")
T.assertEq(echoed[1],    "hello",  "echo[1]")
T.assertEq(echoed[2],    "world",  "echo[2]")

local infoH = rpc._getHandler("info")
local info = infoH({})
T.assertEq(type(info), "table", "info вернул таблицу")
T.assertTrue(info.id ~= nil,      "info.id есть")
T.assertTrue(info.version ~= nil, "info.version есть")
T.assertTrue(info.uptime ~= nil,  "info.uptime есть")

-- Сериализация результата handler'а переживает round-trip.
local serHandler = textutils.serialize(echoed)
local backHandler = textutils.unserialize(serHandler)
T.assertEq(backHandler[1], "hello", "handler result сериализуется корректно")

--------------------------------------------------------------
-- 4. pcall вокруг handler: ошибка → error-фрейм (эмуляция)
--------------------------------------------------------------

rpc.register("test.boom", function() error("nope") end)
local h = rpc._getHandler("test.boom")
local ok, e = pcall(h, {})
T.assertEq(ok, false, "handler с error упал в pcall")
T.assertTrue(tostring(e):find("nope") ~= nil, "текст ошибки виден")
rpc.unregister("test.boom")
