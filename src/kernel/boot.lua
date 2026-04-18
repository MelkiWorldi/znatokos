-- ЗнатокOS: загрузчик
-- Устанавливает глобальный загрузчик модулей, настраивает дисплей,
-- кириллицу, тему, запускает login и desktop.

---------------------------------------------------------------
-- 1. Глобальный загрузчик модулей
---------------------------------------------------------------
if not _G.znatokos then
    _G.znatokos = { VERSION = "0.2.0", loaded = {} }
    function _G.znatokos.use(path)
        if _G.znatokos.loaded[path] then return _G.znatokos.loaded[path] end
        local full = "/znatokos/src/" .. path .. ".lua"
        local fn, err = loadfile(full, nil, _G)
        if not fn then error("znatokos.use(" .. path .. "): " .. tostring(err)) end
        local mod = fn()
        _G.znatokos.loaded[path] = mod
        return mod
    end
end

---------------------------------------------------------------
-- 1b. Перехват вывода UTF-8 → CP1251
---------------------------------------------------------------
local cyr_ok, cyr = pcall(znatokos.use, "util/cyrillic")
if cyr_ok and cyr and cyr.installHooks then cyr.installHooks() end

---------------------------------------------------------------
-- 2. Проверка железа
---------------------------------------------------------------
if not term.isColor or not term.isColor() then
    term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1, 1)
    print("ЗнатокOS: требуется Advanced Computer (цветной экран).")
    print("Продолжить в ч/б режиме? (y/N)")
    local ans = read()
    if ans:lower() ~= "y" then return end
end

---------------------------------------------------------------
-- 3. Splash (пока на встроенном экране — монитор ещё не подключён)
---------------------------------------------------------------
local function splash()
    term.setBackgroundColor(colors.black); term.clear()
    local sw, sh = term.getSize()
    term.setTextColor(colors.yellow)
    local title = "ЗнатокOS v" .. _G.znatokos.VERSION
    term.setCursorPos(math.max(1, math.floor((sw - #title) / 2) + 1),
                      math.max(1, math.floor(sh / 2)))
    term.write(title)
    term.setTextColor(colors.lightGray)
    local sub = "загрузка..."
    term.setCursorPos(math.max(1, math.floor((sw - #sub) / 2) + 1),
                      math.max(2, math.floor(sh / 2) + 1))
    term.write(sub)
    sleep(0.4)
end
splash()

---------------------------------------------------------------
-- 4. Инициализация каталогов
---------------------------------------------------------------
local paths = znatokos.use("fs/paths")
local function ensure(p) if not fs.exists(p) then fs.makeDir(p) end end
ensure(paths.ROOT); ensure(paths.ETC); ensure(paths.VAR)
ensure(paths.VAR .. "/log"); ensure(paths.TMP)
ensure(paths.PKG_DIR); ensure(paths.HOMES)

local log = znatokos.use("kernel/log")
log.info("boot: старт v" .. _G.znatokos.VERSION)

---------------------------------------------------------------
-- 5. Дисплей (monitor / plane)
---------------------------------------------------------------
local display = znatokos.use("kernel/display")
display.start()

---------------------------------------------------------------
-- 6. Тема — применить палитру
---------------------------------------------------------------
local theme = znatokos.use("ui/theme")
theme.applyCurrent()

---------------------------------------------------------------
-- 7. Login
---------------------------------------------------------------
local login = znatokos.use("auth/login")
local vfs   = znatokos.use("fs/vfs")
local user, err = login.run()
if not user then
    log.error("login failed: " .. tostring(err))
    term.setTextColor(colors.red)
    print("Вход невозможен: " .. tostring(err))
    return
end
vfs.setUser(user)
log.info("login: " .. user.user)
ensure(paths.HOMES .. "/" .. user.user)

---------------------------------------------------------------
-- 8. Desktop
---------------------------------------------------------------
local desktop = znatokos.use("ui/desktop")
desktop.run(user)

log.info("boot: завершение сеанса")
term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
term.clear(); term.setCursorPos(1, 1)
print("Сеанс завершён. Напечатайте reboot.")
