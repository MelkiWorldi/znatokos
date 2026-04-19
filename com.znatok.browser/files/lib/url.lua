-- lib/url.lua
-- Упрощённый парсер и нормализатор URL для браузера ZnatokOS.
-- Не полный RFC 3986, но покрывает http/https случаи, нужные браузеру.
-- Экспорты: parse, build, resolve, isUrl, encode, decode, queryParse, queryBuild.

local M = {}

-- Порты по умолчанию для поддерживаемых схем
local DEFAULT_PORTS = {
    http = 80,
    https = 443,
}

-- Кодирует строку в URL-encoded формат.
-- Использует textutils.urlEncode если доступен, иначе резервная реализация.
function M.encode(s)
    if s == nil then return "" end
    s = tostring(s)
    if textutils and textutils.urlEncode then
        return textutils.urlEncode(s)
    end
    -- Резервный вариант: кодируем всё кроме безопасных символов
    return (s:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Декодирует URL-encoded строку.
function M.decode(s)
    if s == nil then return "" end
    s = tostring(s):gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return s
end

-- Простая эвристика: строка похожа на URL?
function M.isUrl(s)
    if type(s) ~= "string" then return false end
    if s:match("^https?://") then return true end
    if s:find("://", 1, true) then return true end
    return false
end

-- Парсит URL-строку в таблицу компонентов.
-- Возвращает таблицу или nil, err.
function M.parse(urlString)
    if type(urlString) ~= "string" or urlString == "" then
        return nil, "empty url"
    end

    -- Извлекаем схему
    local scheme, rest = urlString:match("^([%a][%w%+%-%.]*)://(.*)$")
    if not scheme then
        return nil, "no scheme (not a url)"
    end
    scheme = scheme:lower()

    if scheme ~= "http" and scheme ~= "https" then
        return nil, "unsupported scheme: " .. scheme
    end

    -- Отделяем fragment
    local fragment = ""
    local hashPos = rest:find("#", 1, true)
    if hashPos then
        fragment = rest:sub(hashPos) -- включая "#"
        rest = rest:sub(1, hashPos - 1)
    end

    -- Отделяем query
    local query = ""
    local qPos = rest:find("?", 1, true)
    if qPos then
        query = rest:sub(qPos) -- включая "?"
        rest = rest:sub(1, qPos - 1)
    end

    -- Разделяем host[:port] и path
    local authority, path
    local slashPos = rest:find("/", 1, true)
    if slashPos then
        authority = rest:sub(1, slashPos - 1)
        path = rest:sub(slashPos)
    else
        authority = rest
        path = "/"
    end

    if authority == "" then
        return nil, "empty host"
    end

    -- Разделяем host и port
    local host, port
    local colonPos = authority:find(":", 1, true)
    if colonPos then
        host = authority:sub(1, colonPos - 1)
        local portStr = authority:sub(colonPos + 1)
        port = tonumber(portStr)
        if not port then
            return nil, "invalid port: " .. portStr
        end
    else
        host = authority
        port = DEFAULT_PORTS[scheme]
    end

    if host == "" then
        return nil, "empty host"
    end

    return {
        scheme = scheme,
        host = host:lower(),
        port = port,
        path = path,
        query = query,
        fragment = fragment,
        raw = urlString,
    }
end

-- Собирает URL обратно из таблицы компонентов.
function M.build(parts)
    if type(parts) ~= "table" then
        return nil, "parts must be table"
    end
    local scheme = parts.scheme or "http"
    local host = parts.host or ""
    local port = parts.port
    local path = parts.path or "/"
    local query = parts.query or ""
    local fragment = parts.fragment or ""

    local authority = host
    -- Добавляем порт только если он нестандартный
    if port and port ~= DEFAULT_PORTS[scheme] then
        authority = authority .. ":" .. tostring(port)
    end

    -- Нормализуем query/fragment (добавляем ? и # если нет)
    if query ~= "" and not query:match("^%?") then
        query = "?" .. query
    end
    if fragment ~= "" and not fragment:match("^#") then
        fragment = "#" .. fragment
    end

    return scheme .. "://" .. authority .. path .. query .. fragment
end

-- Возвращает директорию из path: "/a/b/c" -> "/a/b/"
local function dirOf(path)
    if path == "" or path == "/" then return "/" end
    local lastSlash = 0
    for i = #path, 1, -1 do
        if path:sub(i, i) == "/" then
            lastSlash = i
            break
        end
    end
    if lastSlash == 0 then return "/" end
    return path:sub(1, lastSlash)
end

-- Резолвит относительный URL относительно base.
function M.resolve(baseUrl, relativeUrl)
    if type(relativeUrl) ~= "string" or relativeUrl == "" then
        return baseUrl
    end

    -- Абсолютный URL
    if relativeUrl:match("^https?://") then
        return relativeUrl
    end

    local base, err = M.parse(baseUrl)
    if not base then
        return nil, err
    end

    -- Схема-относительный URL (начинается с //)
    if relativeUrl:sub(1, 2) == "//" then
        return base.scheme .. ":" .. relativeUrl
    end

    -- Абсолютный путь (начинается с /)
    if relativeUrl:sub(1, 1) == "/" then
        local authority = base.host
        if base.port and base.port ~= DEFAULT_PORTS[base.scheme] then
            authority = authority .. ":" .. tostring(base.port)
        end
        return base.scheme .. "://" .. authority .. relativeUrl
    end

    -- Query-only
    if relativeUrl:sub(1, 1) == "?" then
        local authority = base.host
        if base.port and base.port ~= DEFAULT_PORTS[base.scheme] then
            authority = authority .. ":" .. tostring(base.port)
        end
        return base.scheme .. "://" .. authority .. base.path .. relativeUrl
    end

    -- Fragment-only
    if relativeUrl:sub(1, 1) == "#" then
        local authority = base.host
        if base.port and base.port ~= DEFAULT_PORTS[base.scheme] then
            authority = authority .. ":" .. tostring(base.port)
        end
        return base.scheme .. "://" .. authority .. base.path .. (base.query or "") .. relativeUrl
    end

    -- Относительный путь: берём директорию base.path + нормализуем `..`/`.`
    local dir = dirOf(base.path)
    local authority = base.host
    if base.port and base.port ~= DEFAULT_PORTS[base.scheme] then
        authority = authority .. ":" .. tostring(base.port)
    end
    local combined = dir .. relativeUrl
    -- RFC 3986 remove_dot_segments (упрощённо)
    local segs = {}
    for seg in combined:gmatch("[^/]+") do
        if seg == ".." then
            if #segs > 0 then table.remove(segs) end
        elseif seg ~= "." then
            segs[#segs + 1] = seg
        end
    end
    local normalized = "/" .. table.concat(segs, "/")
    -- Сохраняем trailing slash если был
    if combined:sub(-1) == "/" and normalized:sub(-1) ~= "/" then
        normalized = normalized .. "/"
    end
    return base.scheme .. "://" .. authority .. normalized
end

-- Парсит query-string в таблицу. Принимает как с префиксом ?, так и без.
function M.queryParse(queryString)
    local result = {}
    if type(queryString) ~= "string" or queryString == "" then
        return result
    end
    -- Убираем ведущий ?
    if queryString:sub(1, 1) == "?" then
        queryString = queryString:sub(2)
    end
    for pair in queryString:gmatch("[^&]+") do
        local k, v = pair:match("^([^=]*)=(.*)$")
        if k then
            result[M.decode(k)] = M.decode(v)
        else
            -- Параметр без значения
            result[M.decode(pair)] = ""
        end
    end
    return result
end

-- Собирает таблицу в query-string с префиксом ?.
function M.queryBuild(tbl)
    if type(tbl) ~= "table" then return "" end
    local parts = {}
    -- Собираем ключи в массив, чтобы результат был детерминирован
    -- (порядок всё равно не гарантируется в spec, но лучше отсортировать)
    local keys = {}
    for k, _ in pairs(tbl) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = tbl[k]
        parts[#parts + 1] = M.encode(k) .. "=" .. M.encode(tostring(v))
    end
    if #parts == 0 then return "" end
    return "?" .. table.concat(parts, "&")
end

return M
