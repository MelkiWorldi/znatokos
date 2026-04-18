-- Парсер и валидатор manifest.lua для приложений ЗнатокOS.
-- Manifest — это Lua-файл, возвращающий таблицу с метаданными приложения.

local capabilities = znatokos.use("kernel/capabilities")

local M = {}

-- Допустимый ID приложения: reverse-dns, латиница/цифры/._-, длина 3..64.
local ID_PATTERN = "^[a-z][a-z0-9._%-]*$"
-- Semver x.y.z (без pre-release).
local SEMVER_PATTERN = "^(%d+)%.(%d+)%.(%d+)$"

-- Загрузить manifest.lua из указанного пути. Возвращает (manifest, err).
function M.load(path)
    if not path or type(path) ~= "string" then
        return nil, "путь не задан"
    end
    if fs and fs.exists and not fs.exists(path) then
        return nil, "файл не найден: " .. path
    end
    local fn, loadErr = loadfile(path, nil, _G)
    if not fn then
        return nil, "ошибка загрузки: " .. tostring(loadErr)
    end
    local ok, result = pcall(fn)
    if not ok then
        return nil, "ошибка выполнения: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "manifest должен возвращать таблицу"
    end
    return result, nil
end

-- Проверка ID по regex и по длине.
local function isValidId(id)
    if type(id) ~= "string" then return false end
    if #id < 3 or #id > 64 then return false end
    return id:match(ID_PATTERN) ~= nil
end

-- Проверка semver.
local function isValidSemver(v)
    if type(v) ~= "string" then return false end
    return v:match(SEMVER_PATTERN) ~= nil
end

-- Проверка на path traversal и абсолютные пути.
local function isSafePath(p)
    if type(p) ~= "string" or #p == 0 then return false end
    if p:sub(1, 1) == "/" then return false end
    if p:sub(1, 1) == "\\" then return false end
    -- нельзя иметь сегмент ".."
    for seg in p:gmatch("[^/\\]+") do
        if seg == ".." then return false end
    end
    return true
end

-- Валидация манифеста. Возвращает (true) или (false, err).
function M.validate(manifest)
    if type(manifest) ~= "table" then
        return false, "manifest не является таблицей"
    end

    -- id
    if manifest.id == nil then
        return false, "отсутствует поле id"
    end
    if not isValidId(manifest.id) then
        return false, "некорректный id: " .. tostring(manifest.id)
    end

    -- name
    if type(manifest.name) ~= "string" or #manifest.name == 0 then
        return false, "отсутствует или пустое поле name"
    end

    -- version
    if manifest.version == nil then
        return false, "отсутствует поле version"
    end
    if not isValidSemver(manifest.version) then
        return false, "некорректная версия (ожидается semver x.y.z): " .. tostring(manifest.version)
    end

    -- author (опционально)
    if manifest.author ~= nil and type(manifest.author) ~= "string" then
        return false, "author должен быть строкой"
    end

    -- description (опционально)
    if manifest.description ~= nil then
        if type(manifest.description) ~= "string" then
            return false, "description должен быть строкой"
        end
        if #manifest.description > 500 then
            return false, "description длиннее 500 символов"
        end
    end

    -- icon (опционально)
    if manifest.icon ~= nil then
        if type(manifest.icon) ~= "table" then
            return false, "icon должен быть таблицей"
        end
        if manifest.icon.glyph ~= nil and type(manifest.icon.glyph) ~= "string" then
            return false, "icon.glyph должен быть строкой"
        end
    end

    -- entry
    if type(manifest.entry) ~= "string" or #manifest.entry == 0 then
        return false, "отсутствует поле entry"
    end
    if not isSafePath(manifest.entry) then
        return false, "entry содержит небезопасный путь: " .. manifest.entry
    end

    -- files
    if type(manifest.files) ~= "table" then
        return false, "отсутствует или некорректное поле files"
    end
    local entryFound = false
    for i = 1, #manifest.files do
        local f = manifest.files[i]
        if type(f) ~= "string" then
            return false, "files[" .. i .. "] не строка"
        end
        if not isSafePath(f) then
            return false, "files содержит небезопасный путь: " .. tostring(f)
        end
        if f == manifest.entry then entryFound = true end
    end
    if not entryFound then
        return false, "entry (" .. manifest.entry .. ") отсутствует в files"
    end

    -- capabilities (опционально)
    if manifest.capabilities ~= nil then
        if type(manifest.capabilities) ~= "table" then
            return false, "capabilities должен быть таблицей"
        end
        for i = 1, #manifest.capabilities do
            local cap = manifest.capabilities[i]
            if type(cap) ~= "string" then
                return false, "capabilities[" .. i .. "] не строка"
            end
            if not capabilities.isValid(cap) then
                return false, "неизвестная capability: " .. cap
            end
        end
    end

    -- min_os_version (опционально)
    if manifest.min_os_version ~= nil then
        if not isValidSemver(manifest.min_os_version) then
            return false, "некорректный min_os_version: " .. tostring(manifest.min_os_version)
        end
    end

    -- deps (опционально)
    if manifest.deps ~= nil then
        if type(manifest.deps) ~= "table" then
            return false, "deps должен быть таблицей"
        end
        for depId, constraint in pairs(manifest.deps) do
            if not isValidId(depId) then
                return false, "некорректный id зависимости: " .. tostring(depId)
            end
            if type(constraint) ~= "string" then
                return false, "constraint для " .. depId .. " должен быть строкой"
            end
        end
    end

    return true
end

-- Разобрать semver в три числа; возвращает nil если не semver.
local function parseSemver(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match(SEMVER_PATTERN)
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c)
end

-- Сравнение semver: -1 если a<b, 0 если равны, 1 если a>b.
function M.versionCompare(a, b)
    local a1, a2, a3 = parseSemver(a)
    local b1, b2, b3 = parseSemver(b)
    if not a1 or not b1 then
        error("versionCompare: некорректный semver (" .. tostring(a) .. ", " .. tostring(b) .. ")")
    end
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    return 0
end

-- Проверка: подходит ли версия под constraint.
-- Поддержка: "1.2.3", ">=1.2.3", ">1.2.3", "<=1.2.3", "<1.2.3", "^1.2.3", "~1.2.3".
function M.versionMatches(version, constraint)
    if type(version) ~= "string" or type(constraint) ~= "string" then return false end
    if not parseSemver(version) then return false end

    -- Снимаем пробелы на краях.
    constraint = constraint:match("^%s*(.-)%s*$")

    local op, rest

    -- Двухсимвольные операторы проверяем первыми.
    if constraint:sub(1, 2) == ">=" then
        op, rest = ">=", constraint:sub(3)
    elseif constraint:sub(1, 2) == "<=" then
        op, rest = "<=", constraint:sub(3)
    elseif constraint:sub(1, 1) == ">" then
        op, rest = ">", constraint:sub(2)
    elseif constraint:sub(1, 1) == "<" then
        op, rest = "<", constraint:sub(2)
    elseif constraint:sub(1, 1) == "^" then
        op, rest = "^", constraint:sub(2)
    elseif constraint:sub(1, 1) == "~" then
        op, rest = "~", constraint:sub(2)
    else
        op, rest = "=", constraint
    end

    rest = rest:match("^%s*(.-)%s*$")
    if not parseSemver(rest) then return false end

    local cmp = M.versionCompare(version, rest)

    if op == "=" then
        return cmp == 0
    elseif op == ">=" then
        return cmp >= 0
    elseif op == ">" then
        return cmp > 0
    elseif op == "<=" then
        return cmp <= 0
    elseif op == "<" then
        return cmp < 0
    elseif op == "^" then
        -- Совместимость по major: version >= rest и тот же major.
        if cmp < 0 then return false end
        local va = parseSemver(version)
        local vb = parseSemver(rest)
        return va == vb
    elseif op == "~" then
        -- Совместимость по major.minor: version >= rest и тот же major.minor.
        if cmp < 0 then return false end
        local va1, va2 = parseSemver(version)
        local vb1, vb2 = parseSemver(rest)
        return va1 == vb1 and va2 == vb2
    end
    return false
end

return M
