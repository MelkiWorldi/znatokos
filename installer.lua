-- ЗнатокOS: установщик
-- Запуск:  wget run <URL installer.lua>
-- либо скопировать и набрать  installer

local DEFAULT_BASE = "https://raw.githubusercontent.com/your-user/znatokos/main/"
local args = { ... }
local BASE = args[1] or DEFAULT_BASE
if BASE:sub(-1) ~= "/" then BASE = BASE .. "/" end

local function info(msg, col)
    term.setTextColor(col or colors.white)
    print(msg)
end

term.clear(); term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("== Установщик ЗнатокOS ==")
term.setTextColor(colors.white)
print("Источник: " .. BASE)
print("")

-- Получаем манифест.
local function fetch(path)
    if not http then
        error("HTTP API отключён в конфиге. Включите http = true в CC: Tweaked")
    end
    local url = BASE .. path
    local h, err = http.get(url)
    if not h then error("Не удалось загрузить " .. url .. ": " .. tostring(err)) end
    local data = h.readAll()
    h.close()
    return data
end

local function writeFile(path, data)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(path, "w")
    if not f then error("Не удалось открыть на запись: " .. path) end
    f.write(data)
    f.close()
end

info("Читаем manifest.lua...", colors.lightGray)
local manData = fetch("manifest.lua")
-- Выполняем манифест как Lua
local fn, loadErr = load(manData, "manifest", "t", _ENV or _G)
if not fn then error("Битый манифест: " .. tostring(loadErr)) end
local manifest = fn()
if not manifest or not manifest.files then error("Манифест пустой") end

local root = manifest.root or "/znatokos"
info(("Устанавливаем %s v%s → %s"):format(manifest.name, manifest.version, root), colors.yellow)

local total = #manifest.files
for i, rel in ipairs(manifest.files) do
    local dst
    if rel == "startup.lua" then
        dst = "/startup.lua"
    elseif rel == "manifest.lua" then
        dst = root .. "/manifest.lua"
    else
        dst = root .. "/" .. rel
    end
    term.setTextColor(colors.lightGray)
    io.write(("[%d/%d] %s\n"):format(i, total, rel))
    local data = fetch(rel)
    writeFile(dst, data)
end

term.setTextColor(colors.lime)
print("")
print("Установка завершена.")
term.setTextColor(colors.white)
print("Наберите  reboot  чтобы загрузить ЗнатокOS.")
