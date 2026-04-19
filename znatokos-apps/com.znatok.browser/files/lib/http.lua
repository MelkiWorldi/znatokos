-- lib/http.lua
-- HTTP-клиент над CC:Tweaked http API.
-- Особенности: автоматические редиректы (до 5), таймауты, простые cookies,
-- обработка gzip (ошибка, поскольку мы читаем только текст).
--
-- Экспорты: get, post, head, newSession (для изолированного cookie jar).

local url = require("url")

local M = {}

-- Максимум редиректов по умолчанию
local DEFAULT_MAX_REDIRECTS = 5
local DEFAULT_TIMEOUT = 15 -- секунд

-- Глобальный (для модуля) cookie jar.
-- Структура: { [host] = { [name] = value, ... } }
local globalCookies = {}

-- Утилита: lowercase таблица заголовков (без изменения исходной)
local function lowerHeaders(headers)
    if not headers then return {} end
    local out = {}
    for k, v in pairs(headers) do
        out[tostring(k):lower()] = v
    end
    return out
end

-- Получить заголовок без учёта регистра
local function getHeader(headers, name)
    if not headers then return nil end
    name = name:lower()
    for k, v in pairs(headers) do
        if tostring(k):lower() == name then
            return v
        end
    end
    return nil
end

-- Парсит Set-Cookie значение: "name=value; Path=/; ...".
-- Возвращает name, value или nil.
local function parseSetCookie(value)
    if type(value) ~= "string" then return nil end
    -- Первый сегмент до ";" содержит name=value
    local firstSeg = value:match("^([^;]+)")
    if not firstSeg then return nil end
    local name, val = firstSeg:match("^%s*([^=]+)=(.*)%s*$")
    if not name then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    val = val:gsub("^%s+", ""):gsub("%s+$", "")
    return name, val
end

-- Сохраняет cookies из response headers в jar по хосту.
local function storeCookies(jar, host, responseHeaders)
    if not responseHeaders then return end
    -- В CC:Tweaked значения заголовков могут быть строкой или таблицей, если несколько.
    local setCookie
    for k, v in pairs(responseHeaders) do
        if tostring(k):lower() == "set-cookie" then
            setCookie = v
            break
        end
    end
    if not setCookie then return end

    local entries = {}
    if type(setCookie) == "table" then
        for _, c in ipairs(setCookie) do entries[#entries + 1] = c end
    else
        -- Простой случай: одна строка
        entries[1] = setCookie
    end

    jar[host] = jar[host] or {}
    for _, entry in ipairs(entries) do
        local name, val = parseSetCookie(entry)
        if name then
            jar[host][name] = val
        end
    end
end

-- Собирает Cookie header для хоста из jar.
local function buildCookieHeader(jar, host)
    local store = jar[host]
    if not store then return nil end
    local parts = {}
    for name, val in pairs(store) do
        parts[#parts + 1] = name .. "=" .. val
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "; ")
end

-- Выполняет один HTTP-запрос через async http.request.
-- Возвращает response, err, errResponse (для совместимости с CC API).
-- response = { status, body, headers, url }
local function doRequest(requestUrl, method, body, headers, timeout)
    if not http or not http.request then
        return nil, "http API unavailable"
    end

    -- Отправляем запрос асинхронно (redirect=false — мы рулим редиректами сами)
    http.request({
        url = requestUrl,
        method = method,
        body = body,
        headers = headers,
        binary = false,
        redirect = false,
    })

    local timer = os.startTimer(timeout or DEFAULT_TIMEOUT)

    while true do
        local ev, p1, p2, p3 = os.pullEvent()

        if ev == "http_success" and p1 == requestUrl then
            os.cancelTimer(timer)
            local handle = p2
            local status = handle.getResponseCode and handle.getResponseCode() or 200
            local respHeaders = handle.getResponseHeaders and handle.getResponseHeaders() or {}
            local bodyText = handle.readAll and handle.readAll() or ""
            if handle.close then handle.close() end

            -- Проверка gzip: мы текст не умеем распаковывать
            local ce = getHeader(respHeaders, "content-encoding")
            if ce and tostring(ce):lower():find("gzip", 1, true) then
                return nil, "gzip content-encoding not supported"
            end

            return {
                status = status,
                body = bodyText,
                headers = respHeaders,
                url = requestUrl,
            }

        elseif ev == "http_failure" and p1 == requestUrl then
            os.cancelTimer(timer)
            local errMsg = p2 or "http failure"
            local errHandle = p3
            -- Если есть errResponse — это валидный HTTP-ответ с ошибочным кодом (4xx/5xx)
            if errHandle then
                local status = errHandle.getResponseCode and errHandle.getResponseCode() or 0
                local respHeaders = errHandle.getResponseHeaders and errHandle.getResponseHeaders() or {}
                local bodyText = errHandle.readAll and errHandle.readAll() or ""
                if errHandle.close then errHandle.close() end
                return {
                    status = status,
                    body = bodyText,
                    headers = respHeaders,
                    url = requestUrl,
                }
            end
            return nil, errMsg

        elseif ev == "timer" and p1 == timer then
            return nil, "timeout after " .. tostring(timeout) .. "s"
        end
        -- Иначе продолжаем — событие не наше
    end
end

-- Собирает заголовки с учётом cookies и user-supplied.
local function buildHeaders(userHeaders, jar, host)
    local headers = {}
    if userHeaders then
        for k, v in pairs(userHeaders) do
            headers[k] = v
        end
    end
    -- Добавляем Cookie только если не задан явно
    local hasCookie = false
    for k, _ in pairs(headers) do
        if tostring(k):lower() == "cookie" then
            hasCookie = true
            break
        end
    end
    if not hasCookie then
        local cookieHeader = buildCookieHeader(jar, host)
        if cookieHeader then
            headers["Cookie"] = cookieHeader
        end
    end
    return headers
end

-- Общий запрос с поддержкой редиректов и cookies.
-- method: "GET" / "POST" / ...
-- requestUrl: исходный URL
-- body: строка или nil
-- opts: { headers, timeout, followRedirects, cookies (jar) }
local function request(method, requestUrl, body, opts)
    opts = opts or {}
    local timeout = opts.timeout or DEFAULT_TIMEOUT
    local followRedirects = opts.followRedirects
    if followRedirects == nil then followRedirects = true end
    local maxRedirects = DEFAULT_MAX_REDIRECTS
    local jar = opts.cookies or globalCookies

    local currentUrl = requestUrl
    local redirects = 0
    local currentMethod = method
    local currentBody = body

    while true do
        local parsed, perr = url.parse(currentUrl)
        if not parsed then
            return nil, "bad url: " .. tostring(perr)
        end

        local headers = buildHeaders(opts.headers, jar, parsed.host)

        local resp, err = doRequest(currentUrl, currentMethod, currentBody, headers, timeout)
        if not resp then
            return nil, err
        end

        -- Сохраняем cookies
        storeCookies(jar, parsed.host, resp.headers)

        local status = resp.status
        local isRedirect = status == 301 or status == 302 or status == 303
            or status == 307 or status == 308

        if isRedirect and followRedirects then
            if redirects >= maxRedirects then
                return nil, "too many redirects (" .. maxRedirects .. ")"
            end
            local location = getHeader(resp.headers, "location")
            if not location or location == "" then
                -- Редирект без Location — возвращаем как есть
                resp.finalUrl = currentUrl
                return resp
            end
            local nextUrl = url.resolve(currentUrl, location)
            redirects = redirects + 1
            currentUrl = nextUrl
            -- Для 303 (и обычно 301/302 в браузерах) переходим на GET без тела
            if status == 303 or status == 301 or status == 302 then
                currentMethod = "GET"
                currentBody = nil
            end
            -- Продолжаем цикл
        else
            resp.finalUrl = currentUrl
            return resp
        end
    end
end

-- Публичный GET.
function M.get(requestUrl, opts)
    return request("GET", requestUrl, nil, opts)
end

-- Публичный POST. body может быть строкой или таблицей (form-urlencoded).
function M.post(requestUrl, body, opts)
    opts = opts or {}
    local contentType = opts.contentType or "application/x-www-form-urlencoded"
    local sendBody

    if type(body) == "table" then
        -- Сериализуем как form-urlencoded
        local parts = {}
        for k, v in pairs(body) do
            parts[#parts + 1] = url.encode(tostring(k)) .. "=" .. url.encode(tostring(v))
        end
        sendBody = table.concat(parts, "&")
    else
        sendBody = body or ""
    end

    -- Дополняем headers Content-Type если не задан
    local headers = {}
    if opts.headers then
        for k, v in pairs(opts.headers) do headers[k] = v end
    end
    local hasCt = false
    for k, _ in pairs(headers) do
        if tostring(k):lower() == "content-type" then hasCt = true; break end
    end
    if not hasCt then
        headers["Content-Type"] = contentType
    end

    local newOpts = {}
    for k, v in pairs(opts) do newOpts[k] = v end
    newOpts.headers = headers

    return request("POST", requestUrl, sendBody, newOpts)
end

-- HEAD — CC не умеет нативно, делаем GET и отбрасываем тело.
function M.head(requestUrl, opts)
    local resp, err = M.get(requestUrl, opts)
    if not resp then return nil, err end
    resp.body = ""
    return resp
end

-- Создаёт изолированную сессию с собственным cookie jar.
function M.newSession()
    local jar = {}
    local session = {}
    function session.get(u, opts)
        opts = opts or {}
        opts.cookies = jar
        return M.get(u, opts)
    end
    function session.post(u, body, opts)
        opts = opts or {}
        opts.cookies = jar
        return M.post(u, body, opts)
    end
    function session.head(u, opts)
        opts = opts or {}
        opts.cookies = jar
        return M.head(u, opts)
    end
    function session.cookies() return jar end
    function session.clearCookies()
        for k in pairs(jar) do jar[k] = nil end
    end
    return session
end

-- Очистить глобальный cookie jar (для тестов/отладки).
function M.clearCookies()
    for k in pairs(globalCookies) do globalCookies[k] = nil end
end

return M
