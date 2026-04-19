-- lib/search.lua
-- Модуль поиска для браузера ZnatokOS.
-- Преобразует произвольный текст в URL поисковой выдачи, опционально
-- парсит результаты из HTML-страницы поисковика.
--
-- Простой путь: M.buildSearchUrl(query, engine) -> URL (навигация браузером).
-- Сложный путь: M.quickSearch(query, opts, deps) -> массив { title, url, snippet }.
--
-- Зависимости (url/http/html) передаются через параметр deps у quickSearch —
-- это обход ограничений sandbox ZnatokOS, в котором require может не работать.

local M = {}

-- ---------------------------------------------------------------
-- Публичные утилиты
-- ---------------------------------------------------------------

-- Выглядит ли input как поисковый запрос (а не URL).
-- Реализация простая: если url.isUrl возвращает false — это поиск.
-- Модуль url можно передать через второй аргумент, иначе используем
-- переданный при инициализации (см. M._setUrlLib) или глобальный.
local _urlLib = nil

function M._setUrlLib(lib)
    _urlLib = lib
end

local function resolveUrl(urlLib)
    return urlLib or _urlLib
end

function M.isSearchQuery(input, urlLib)
    if type(input) ~= "string" or input == "" then return false end
    local u = resolveUrl(urlLib)
    if u and u.isUrl then
        return not u.isUrl(input)
    end
    -- Фоллбэк: если нет схемы и нет точки с буквами после — скорее поиск.
    if input:match("^%a[%w%+%-%.]*://") then return false end
    return true
end

-- ---------------------------------------------------------------
-- Построение URL поисковой выдачи
-- ---------------------------------------------------------------

-- Простая percent-кодировка (fallback, если нет url.encode).
local function percentEncode(s)
    if s == nil then return "" end
    s = tostring(s)
    return (s:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Пытаемся использовать url.encode если модуль доступен.
local function encode(s, urlLib)
    local u = resolveUrl(urlLib)
    if u and u.encode then
        return u.encode(s)
    end
    return percentEncode(s)
end

function M.buildSearchUrl(query, engine, urlLib)
    engine = engine or "ddg"
    local q = encode(query or "", urlLib)
    if engine == "google" then
        return "https://www.google.com/search?q=" .. q .. "&hl=ru"
    end
    -- По умолчанию — DuckDuckGo (HTML-версия без JS).
    return "https://html.duckduckgo.com/html/?q=" .. q
end

-- ---------------------------------------------------------------
-- Парсинг результатов
-- ---------------------------------------------------------------

-- Обрезает пробелы по краям.
local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Проверяет, содержит ли атрибут class указанный класс.
local function hasClass(node, className)
    if not node or not node.attrs then return false end
    local cls = node.attrs.class
    if type(cls) ~= "string" or cls == "" then return false end
    -- Проверяем по границам слова, чтобы "result__a" не матчил "result__a-extra".
    for c in cls:gmatch("%S+") do
        if c == className then return true end
    end
    -- Дополнительно — простой поиск вхождения (совместимо с DDG разметкой).
    return cls:find(className, 1, true) ~= nil
end

-- Находит ближайший предок с заданным классом (обход через поиск по дереву).
-- Используется чтобы для <a> найти родителя-результата (где лежит snippet).
-- Так как наш html.lua не хранит parent-ссылок, применяется редко.

-- Находит первый потомок-элемент с нужным классом.
local function findDescendantByClass(root, className, htmlLib)
    if not root or not root.children then return nil end
    for _, ch in ipairs(root.children) do
        if ch.kind == "elem" then
            if hasClass(ch, className) then
                return ch
            end
            local deeper = findDescendantByClass(ch, className, htmlLib)
            if deeper then return deeper end
        end
    end
    return nil
end

-- Декодирует href из DDG-редиректа //duckduckgo.com/l/?uddg=<encoded>.
local function unwrapDdgHref(href, urlLib)
    if type(href) ~= "string" or href == "" then return href end
    if href:find("uddg=", 1, true) then
        local enc = href:match("uddg=([^&]+)")
        if enc then
            local u = resolveUrl(urlLib)
            if u and u.decode then
                return u.decode(enc)
            end
            -- Ручной декод.
            enc = enc:gsub("+", " ")
            return (enc:gsub("%%(%x%x)", function(h)
                return string.char(tonumber(h, 16))
            end))
        end
    end
    -- Схема-относительный URL — добавим https.
    if href:sub(1, 2) == "//" then
        return "https:" .. href
    end
    return href
end

-- Декодирует href из google-редиректа /url?q=<actual>&...
local function unwrapGoogleHref(href, urlLib)
    if type(href) ~= "string" or href == "" then return href end
    local real = href:match("^/url%?q=([^&]+)")
    if not real then
        real = href:match("[?&]q=([^&]+)")
        -- Используем только если исходная ссылка — /url?...
        if not href:find("^/url") then real = nil end
    end
    if real then
        local u = resolveUrl(urlLib)
        if u and u.decode then
            return u.decode(real)
        end
        real = real:gsub("+", " ")
        return (real:gsub("%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end))
    end
    return href
end

-- Парсер выдачи DuckDuckGo HTML.
local function parseDuckDuckGo(dom, htmlLib, urlLib)
    local results = {}
    if not (dom and htmlLib and htmlLib.findAll) then return results end

    local aTags = htmlLib.findAll(dom, "a") or {}
    for _, a in ipairs(aTags) do
        if hasClass(a, "result__a") then
            local href = a.attrs and a.attrs.href or ""
            local title = trim(htmlLib.getText and htmlLib.getText(a) or "")
            if href ~= "" and title ~= "" then
                href = unwrapDdgHref(href, urlLib)
                results[#results + 1] = {
                    url = href,
                    title = title,
                    snippet = "",
                }
            end
        end
    end

    -- Попробуем прикрепить snippet: ищем все элементы с классом result__snippet.
    -- Их должно быть примерно столько же, сколько результатов; сопоставляем по
    -- порядку появления в документе — этого обычно достаточно.
    local snippets = {}
    local function walk(node)
        if not node then return end
        if node.kind == "elem" then
            if hasClass(node, "result__snippet") then
                snippets[#snippets + 1] = trim(htmlLib.getText(node))
                return
            end
            if node.children then
                for _, ch in ipairs(node.children) do walk(ch) end
            end
        end
    end
    walk(dom)

    for i, r in ipairs(results) do
        if snippets[i] then r.snippet = snippets[i] end
    end

    return results
end

-- Парсер выдачи Google. Структура: <a href="/url?q=..."><h3>Title</h3></a>,
-- описание — в элементе с классом VwiC3b.
local function parseGoogle(dom, htmlLib, urlLib)
    local results = {}
    if not (dom and htmlLib and htmlLib.findAll) then return results end

    local aTags = htmlLib.findAll(dom, "a") or {}
    for _, a in ipairs(aTags) do
        local href = a.attrs and a.attrs.href
        if type(href) == "string" and href:find("^/url%?q=") then
            -- Ищем h3 внутри ссылки — это title результата.
            local h3 = nil
            if htmlLib.findAll then
                local found = htmlLib.findAll(a, "h3")
                if found and #found > 0 then h3 = found[1] end
            end
            if h3 then
                local title = trim(htmlLib.getText(h3))
                local realHref = unwrapGoogleHref(href, urlLib)
                if title ~= "" and realHref ~= "" then
                    results[#results + 1] = {
                        url = realHref,
                        title = title,
                        snippet = "",
                    }
                end
            end
        end
    end

    -- Snippets: ищем span.VwiC3b — собираем в порядке появления.
    local snippets = {}
    local function walk(node)
        if not node then return end
        if node.kind == "elem" then
            if hasClass(node, "VwiC3b") then
                snippets[#snippets + 1] = trim(htmlLib.getText(node))
                return
            end
            if node.children then
                for _, ch in ipairs(node.children) do walk(ch) end
            end
        end
    end
    walk(dom)

    for i, r in ipairs(results) do
        if snippets[i] then r.snippet = snippets[i] end
    end

    return results
end

function M.parseResults(htmlBody, engine, htmlLib, urlLib)
    if type(htmlBody) ~= "string" or htmlBody == "" then return {} end
    if not (htmlLib and htmlLib.parse) then return {} end

    local ok, dom = pcall(htmlLib.parse, htmlBody)
    if not ok or not dom then return {} end

    local results
    if engine == "google" then
        local okP, res = pcall(parseGoogle, dom, htmlLib, urlLib)
        results = (okP and res) or {}
    else
        local okP, res = pcall(parseDuckDuckGo, dom, htmlLib, urlLib)
        results = (okP and res) or {}
    end

    return results or {}
end

-- ---------------------------------------------------------------
-- Полный цикл: запрос -> HTTP -> парсинг
-- ---------------------------------------------------------------

-- opts = { engine = "ddg"|"google", timeout = seconds }
-- deps = { http = <http-module>, url = <url-module>, html = <html-module> }
function M.quickSearch(query, opts, deps)
    opts = opts or {}
    deps = deps or {}
    local httpLib = deps.http
    local urlLib  = deps.url
    local htmlLib = deps.html

    if type(query) ~= "string" or query == "" then
        return nil, "пустой запрос"
    end
    if not httpLib or not httpLib.get then
        return nil, "http модуль недоступен"
    end
    if not htmlLib or not htmlLib.parse then
        return nil, "html модуль недоступен"
    end

    local engine = opts.engine or "ddg"
    local timeout = opts.timeout or 15

    local function runOne(eng)
        local searchUrl = M.buildSearchUrl(query, eng, urlLib)
        local ok, resp, err = pcall(httpLib.get, searchUrl, { timeout = timeout })
        if not ok then
            return nil, tostring(resp)
        end
        if not resp then
            return nil, tostring(err or "http error")
        end
        if resp.status and resp.status >= 400 then
            return nil, "HTTP " .. tostring(resp.status)
        end
        local results = M.parseResults(resp.body or "", eng, htmlLib, urlLib)
        return results or {}, nil
    end

    local results, err = runOne(engine)
    if results and #results > 0 then
        return results
    end

    -- Фоллбэк: если ddg вернул пусто — пробуем google.
    if engine == "ddg" then
        local gRes, gErr = runOne("google")
        if gRes and #gRes > 0 then
            return gRes
        end
        err = gErr or err
    end

    -- Никаких результатов — возвращаем пустой массив, а не nil.
    -- Ошибку возвращаем только если была реальная проблема с сетью.
    if err and (not results or #results == 0) then
        return {}, err
    end
    return results or {}
end

-- Возвращает URL поисковой выдачи — браузер откроет его как обычную страницу.
function M.openSearch(query, engine, urlLib)
    return M.buildSearchUrl(query, engine or "ddg", urlLib)
end

return M
