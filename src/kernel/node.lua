-- Идентичность узла ЗнатокOS в сети.
-- Хранит стабильные имя/идентификатор/роль компьютера в /znatokos/etc/node.cfg.
local paths = znatokos.use("fs/paths")
local log   = znatokos.use("kernel/log")

local M = {}

-- Допустимые роли узла с русскими описаниями.
M.VALID_ROLES = {
    workstation = "рабочая станция",
    server      = "сервер",
    turtle      = "черепаха",
    pocket      = "карманный компьютер",
    monitor     = "терминал/монитор",
}

-- Текущее состояние (в памяти). Инициализируется через load().
local state = nil

-- Путь к конфигу формируется на лету, чтобы тесты могли подменять paths.ETC.
local function cfgPath()
    return paths.ETC .. "/node.cfg"
end

-- Генерация 16 hex-символов (8 случайных байт) на базе math.random.
local function randHex()
    math.randomseed(os.epoch("utc"))
    local parts = {}
    for i = 1, 16 do
        parts[i] = string.format("%x", math.random(0, 15))
    end
    return table.concat(parts)
end

-- Создаёт свежую identity с дефолтами.
local function makeDefault()
    local cid = 0
    if os and os.getComputerID then cid = os.getComputerID() end
    return {
        id         = "znatok-" .. randHex(),
        name       = "computer-" .. tostring(cid),
        role       = "workstation",
        created_at = os.epoch("utc"),
    }
end

-- Пишет state в node.cfg через textutils.serialize.
function M.save()
    if not state then return false, "нет состояния для сохранения" end
    if not fs.exists(paths.ETC) then fs.makeDir(paths.ETC) end
    local f = fs.open(cfgPath(), "w")
    if not f then
        log.error("node: не удалось открыть " .. cfgPath() .. " на запись")
        return false, "не удалось открыть файл"
    end
    f.write("return " .. textutils.serialize(state))
    f.close()
    return true
end

-- Читает конфиг; если нет — генерит новый и сохраняет.
function M.load()
    local path = cfgPath()
    if fs.exists(path) then
        local fn, err = loadfile(path, nil, _G)
        if fn then
            local ok, data = pcall(fn)
            if ok and type(data) == "table" and data.id and data.name and data.role then
                state = data
                if not state.created_at then state.created_at = os.epoch("utc") end
                return state
            end
            log.warn("node: повреждён " .. path .. ", пересоздаю")
        else
            log.warn("node: ошибка loadfile " .. tostring(err) .. ", пересоздаю")
        end
    end
    state = makeDefault()
    M.save()
    log.info("node: создана новая identity id=" .. state.id)
    return state
end

-- Гарантирует, что state загружен.
local function ensure()
    if not state then M.load() end
    return state
end

function M.getId()        return ensure().id end
function M.getName()      return ensure().name end
function M.getRole()      return ensure().role end
function M.getCreatedAt() return ensure().created_at end

-- Возвращает копию таблицы identity (для отладки/CLI).
function M.get()
    local s = ensure()
    return { id = s.id, name = s.name, role = s.role, created_at = s.created_at }
end

-- Проверка имени: 1..32 байта; буквы (ASCII), цифры, _ - .
-- Lua-паттерны работают по байтам, поэтому UTF-8 символы не пропустим.
local function validName(name)
    if type(name) ~= "string" then return false, "имя должно быть строкой" end
    local len = #name
    if len < 1 or len > 32 then
        return false, "длина имени должна быть от 1 до 32 символов"
    end
    if not name:match("^[%w_%-%.]+$") then
        return false, "имя может содержать только латинские буквы, цифры, _ - ."
    end
    return true
end

function M.setName(name)
    local ok, err = validName(name)
    if not ok then return false, err end
    ensure().name = name
    local okSave, errSave = M.save()
    if not okSave then return false, errSave end
    log.info("node: name=" .. name)
    return true
end

function M.setRole(role)
    if type(role) ~= "string" or M.VALID_ROLES[role] == nil then
        return false, "неизвестная роль: " .. tostring(role)
    end
    ensure().role = role
    local okSave, errSave = M.save()
    if not okSave then return false, errSave end
    log.info("node: role=" .. role)
    return true
end

-- Сбрасывает identity: новый id и created_at, имя/роль сохраняются.
function M.reset()
    local s = ensure()
    local old = s.id
    s.id = "znatok-" .. randHex()
    s.created_at = os.epoch("utc")
    local ok, err = M.save()
    if not ok then return false, err end
    log.warn("node: reset id " .. old .. " -> " .. s.id)
    return true, s.id
end

return M
