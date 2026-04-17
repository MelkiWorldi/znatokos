-- ЗнатокOS: загрузчик
-- Устанавливает глобальный модульный загрузчик znatokos.use(),
-- инициализирует каталоги, показывает splash, запускает login и desktop.

---------------------------------------------------------------
-- 1. Глобальный загрузчик модулей
---------------------------------------------------------------
if not _G.znatokos then
    _G.znatokos = { VERSION = "0.1.0", loaded = {} }
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
-- 2. Проверка железа
---------------------------------------------------------------
local w, h = term.getSize()
if not term.isColor or not term.isColor() then
    term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1, 1)
    print("ЗнатокOS: требуется Advanced Computer (цветной экран).")
    print("На обычном компьютере доступен только базовый шелл.")
    print("Продолжить в ч/б режиме? (y/N)")
    local ans = read()
    if ans:lower() ~= "y" then
        term.setTextColor(colors.white)
        return
    end
end

---------------------------------------------------------------
-- 3. Splash
---------------------------------------------------------------
local function splash()
    local paintutils_ok = paintutils ~= nil
    term.setBackgroundColor(colors.black); term.clear()
    local lines = {
        "  ________                _____ _______ ______   _   _  ____   _____ ",
        " |__  /    \\    |\\    | / ____|__   __|  __  \\ | | / |/  _ \\ / ____|",
        "   / // /\\ \\   | \\ \\  || |___   | |  | |  | | |/ / | | | | | |  __  ",
        "  / // ____ \\  | |\\ \\ || ___ \\  | |  | |  | |  _ \\ | | | | | |_| | ",
        " /_//_/    \\_\\ |_| \\___||_____/ |_|  |_____/_| \\_\\|_| \\_|_/ \\___/  ",
        "",
        "              ЗнатокOS v" .. _G.znatokos.VERSION,
        "             загрузка...",
    }
    local sw, sh = term.getSize()
    term.setTextColor(colors.cyan)
    local startY = math.floor((sh - #lines) / 2)
    for i, l in ipairs(lines) do
        local x = math.max(1, math.floor((sw - #l) / 2))
        term.setCursorPos(x, startY + i - 1)
        if i == 7 then term.setTextColor(colors.yellow)
        elseif i == 8 then term.setTextColor(colors.lightGray)
        else term.setTextColor(colors.cyan) end
        term.write(l)
    end
    sleep(0.6)
end

splash()

---------------------------------------------------------------
-- 4. Инициализация каталогов
---------------------------------------------------------------
local paths = znatokos.use("fs/paths")
local function ensure(p) if not fs.exists(p) then fs.makeDir(p) end end
ensure(paths.ROOT)
ensure(paths.ETC)
ensure(paths.VAR)
ensure(paths.VAR .. "/log")
ensure(paths.TMP)
ensure(paths.PKG_DIR)
ensure(paths.HOMES)

local log = znatokos.use("kernel/log")
log.info("boot: старт v" .. _G.znatokos.VERSION)

---------------------------------------------------------------
-- 5. Login
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
-- 6. Desktop
---------------------------------------------------------------
local desktop = znatokos.use("ui/desktop")
desktop.run(user)

log.info("boot: завершение сеанса")
term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
term.clear(); term.setCursorPos(1, 1)
print("Сеанс завершён. Напечатайте reboot.")
