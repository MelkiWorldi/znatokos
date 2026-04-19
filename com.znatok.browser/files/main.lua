-- main.lua — скелет браузера ZnatokOS v0.3.0 (iter 8: вкладки).
-- Возможности: адрес-бар, загрузка URL, рендер HTML, прокрутка, вкладки.
-- НЕ реализовано пока: закладки, редактирование полей формы.

local user = (znatokos and znatokos.app and znatokos.app.user) or {}
local appDir = (znatokos and znatokos.app and znatokos.app.dir) or ""

-- Загрузка модулей приложения.
local function loadLib(rel)
    local path = appDir .. "/lib/" .. rel
    local chunk, err = loadfile(path)
    if not chunk then
        return nil, err
    end
    local ok, mod = pcall(chunk)
    if not ok then return nil, mod end
    return mod
end

local http   = loadLib("http.lua")
local urlLib = loadLib("url.lua")
local html   = loadLib("html.lua")
local layout = loadLib("layout.lua")
local render = loadLib("render.lua")
local link   = loadLib("link.lua")
local form   = loadLib("form.lua")
local js     = loadLib("js.lua")
local tabs   = loadLib("tabs.lua")
local search = loadLib("search.lua")
local css    = loadLib("css.lua")
-- Имя `bmstore`, чтобы не конфликтовать с глобальным `store`.
local bmstore = loadLib("store.lua")

-- Загружаем тему (themes/default.lua, не lib/).
local themeFromFile
do
    local base = (znatokos and znatokos.app and znatokos.app.dir) or ""
    local path = base .. "/themes/default.lua"
    local okT, chunkOrErr = pcall(loadfile, path)
    if okT and chunkOrErr then
        local okR, tbl = pcall(chunkOrErr)
        if okR and type(tbl) == "table" then themeFromFile = tbl end
    end
end

-- Пробрасываем url-модуль в link.lua (у link.lua нет require в CC).
if link and link._setUrlLib and urlLib then
    link._setUrlLib(urlLib)
end

-- Пробрасываем url-модуль в search.lua по той же причине.
if search and search._setUrlLib and urlLib then
    search._setUrlLib(urlLib)
end

-- Инициализация FS-хранилища закладок/истории (если модуль доступен).
if bmstore and user and user.home then
    pcall(bmstore.init, user.home)
end

-- ---------------------------------------------------------------
-- Состояние
-- ---------------------------------------------------------------

-- Глобальное состояние приложения (не относящееся к конкретной странице).
local appState = {
    urlInput  = "http://85.239.37.114/store/index.json",
    cursorPos = nil,
    focus     = "address", -- "address" | "page"
    running   = true,
    altDown   = false,
    ctrlDown  = false,
}
appState.cursorPos = #appState.urlInput + 1

-- Состояние вкладок.
local tabState = tabs.newState()
tabState.tabs[1].url = appState.urlInput

local function currentTab() return tabs.current(tabState) end

local function pushHistory(tab, u)
    local h = tab.history
    while #h.stack > h.idx do
        table.remove(h.stack)
    end
    h.stack[#h.stack + 1] = u
    h.idx = #h.stack
end

local THEME = {
    bg              = colors.white,
    fg              = colors.black,
    chrome_bg       = colors.lightGray,
    chrome_fg       = colors.black,
    accent          = colors.blue,
    status_bg       = colors.gray,
    status_fg       = colors.white,
    link            = colors.blue,
    tab_active_fg   = colors.black,
    tab_active_bg   = colors.white,
    tab_inactive_fg = colors.black,
    tab_inactive_bg = colors.lightGray,
}

-- Мёрджим тему из файла (если загрузилась). Значения из themes/default.lua
-- перекрывают захардкоженные дефолты — так можно менять тему без правки main.lua.
if themeFromFile then
    for k, v in pairs(themeFromFile) do THEME[k] = v end
    -- Алиас: render.lua ожидает поле .link для ссылок.
    THEME.link = THEME.link or THEME.link_fg or colors.blue
end

-- ---------------------------------------------------------------
-- Геометрия
-- ---------------------------------------------------------------

-- Строки сверху вниз:
--   tabBarY = 1   — вкладки
--   addrY   = 2   — адрес-бар
--   sepY    = 3   — разделитель
--   contentY1..contentY2 — контент
--   statusY = h   — статус
local function layoutGeom()
    local w, h = term.getSize()
    return {
        w = w, h = h,
        tabBarY   = 1,
        addrY     = 2,
        sepY      = 3,
        contentY1 = 4,
        contentY2 = h - 1,
        statusY   = h,
        urlFieldX1 = 6,
        urlFieldX2 = w - 6,
        goBtnX1  = w - 4,
        goBtnX2  = w - 1,
    }
end

-- Последние зоны tab-bar для hit-test.
local tabZones = {}

-- ---------------------------------------------------------------
-- Отрисовка
-- ---------------------------------------------------------------

local function drawTabBar(g)
    tabZones = tabs.renderBar(term, tabState, {
        y = g.tabBarY,
        width = g.w,
        theme = {
            active_fg   = THEME.tab_active_fg,
            active_bg   = THEME.tab_active_bg,
            inactive_fg = THEME.tab_inactive_fg,
            inactive_bg = THEME.tab_inactive_bg,
            accent      = THEME.accent,
        },
    })
end

local function drawChrome(g)
    term.setBackgroundColor(THEME.chrome_bg)
    term.setTextColor(THEME.chrome_fg)
    term.setCursorPos(1, g.addrY)
    term.write(string.rep(" ", g.w))

    term.setCursorPos(1, g.addrY)
    term.write("URL: ")

    local fieldW = g.urlFieldX2 - g.urlFieldX1 + 1
    term.setCursorPos(g.urlFieldX1, g.addrY)
    if appState.focus == "address" then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    else
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.gray)
    end
    local shown = appState.urlInput
    if #shown > fieldW then shown = shown:sub(-fieldW) end
    shown = shown .. string.rep(" ", math.max(0, fieldW - #shown))
    term.write(shown)

    term.setCursorPos(g.goBtnX1 - 1, g.addrY)
    term.setBackgroundColor(THEME.chrome_bg)
    term.setTextColor(THEME.chrome_fg)
    term.write(" ")
    term.setBackgroundColor(THEME.accent)
    term.setTextColor(colors.white)
    term.setCursorPos(g.goBtnX1, g.addrY)
    term.write("[GO]")

    term.setBackgroundColor(THEME.bg)
    term.setTextColor(colors.gray)
    term.setCursorPos(1, g.sepY)
    term.write(string.rep("-", g.w))
end

local function drawContent(g)
    local vpH = g.contentY2 - g.contentY1 + 1
    if vpH < 1 then return end

    local tab = currentTab()
    if tab.boxes and render then
        render.draw(nil, tab.boxes, {
            x = 1, y = g.contentY1,
            width = g.w, height = vpH,
            scrollY = tab.scrollY,
        }, { bg = THEME.bg, fg = THEME.fg })
    else
        term.setBackgroundColor(THEME.bg)
        term.setTextColor(colors.gray)
        for y = g.contentY1, g.contentY2 do
            term.setCursorPos(1, y)
            term.write(string.rep(" ", g.w))
        end
        term.setCursorPos(2, g.contentY1 + 1)
        term.write("Введите URL и нажмите Enter.")
        term.setCursorPos(2, g.contentY1 + 2)
        term.write("Tab — фокус, стрелки — прокрутка, Ctrl+T — новая вкладка.")
    end
end

-- Подсказки горячих клавиш, подбираемые по доступной ширине.
local FOOTER_HINTS = {
    "Esc выход  Ctrl+T новая  Ctrl+W закрыть  Ctrl+D закладка  Ctrl+H история",
    "Esc выход  Ctrl+T новая  Ctrl+D закладка  Ctrl+H история",
    "Ctrl+T новая  Ctrl+D закладка  Ctrl+H история",
    "Ctrl+D закладка  Ctrl+H история",
    "Ctrl+D  Ctrl+H",
}

local function pickFooterHint(maxW)
    if maxW <= 0 then return "" end
    for _, h in ipairs(FOOTER_HINTS) do
        if #h <= maxW then return h end
    end
    return ""
end

local function drawStatus(g)
    local tab = currentTab()
    term.setCursorPos(1, g.statusY)
    term.setBackgroundColor(THEME.status_bg)
    term.setTextColor(THEME.status_fg)
    local crumb = ""
    local h = tab.history
    if h.idx > 1 then crumb = crumb .. "<" else crumb = crumb .. " " end
    if h.idx < #h.stack then crumb = crumb .. ">" else crumb = crumb .. " " end

    local bmMark = ""
    if bmstore and user and user.home and tab.url and tab.url ~= "" then
        local ok, isBm = pcall(bmstore.isBookmarked, user.home, tab.url)
        if ok and isBm then bmMark = "[*] " end
    end

    local left = crumb .. " " .. bmMark .. "Статус: " .. tostring(tab.status)
    -- Справа — подсказки, если осталось место (минимум 2 пробела-разделителя).
    local roomForHint = g.w - #left - 2
    local hint = pickFooterHint(roomForHint)
    local s
    if hint ~= "" then
        local pad = g.w - #left - #hint
        if pad < 1 then pad = 1 end
        s = left .. string.rep(" ", pad) .. hint
    else
        s = left
    end
    if #s > g.w then s = s:sub(1, g.w) end
    s = s .. string.rep(" ", g.w - #s)
    term.write(s)
end

local function redraw()
    local g = layoutGeom()
    term.setBackgroundColor(THEME.bg)
    term.clear()
    drawTabBar(g)
    drawChrome(g)
    drawContent(g)
    drawStatus(g)

    if appState.focus == "address" then
        local fieldW = g.urlFieldX2 - g.urlFieldX1 + 1
        local text = appState.urlInput
        local cp = appState.cursorPos or (#text + 1)
        local offset = 0
        if #text > fieldW then offset = #text - fieldW end
        local cx = g.urlFieldX1 + (cp - 1 - offset)
        if cx < g.urlFieldX1 then cx = g.urlFieldX1 end
        if cx > g.urlFieldX2 then cx = g.urlFieldX2 end
        term.setCursorPos(cx, g.addrY)
        term.setTextColor(colors.black)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

-- ---------------------------------------------------------------
-- Извлечение <title>
-- ---------------------------------------------------------------

local function extractTitle(dom)
    if not (dom and html and html.findAll) then return nil end
    local nodes = html.findAll(dom, "title") or {}
    for _, n in ipairs(nodes) do
        if n.children then
            for _, ch in ipairs(n.children) do
                if ch.type == "text" and ch.text and ch.text ~= "" then
                    local t = ch.text:gsub("^%s+", ""):gsub("%s+$", "")
                    if t ~= "" then return t end
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------
-- Навигация
-- ---------------------------------------------------------------

local function navigate(u, opts)
    opts = opts or {}
    local tab = currentTab()

    if not u or u == "" then
        tab.status = "пустой URL"
        return
    end

    if urlLib and urlLib.isUrl and not urlLib.isUrl(u) then
        -- Если ввод не похож на URL — трактуем как поисковый запрос.
        -- Эвристика: есть пробел или отсутствует точка — точно поиск.
        -- Иначе (например "example.com") — добавляем схему http://.
        local looksLikeHost = (not u:find("%s")) and u:find("%.") ~= nil
        if looksLikeHost then
            u = "http://" .. u
        elseif search and search.buildSearchUrl then
            u = search.buildSearchUrl(u, "ddg", urlLib)
        else
            u = "http://" .. u
        end
    end

    tab.status = "загрузка " .. u .. "..."
    redraw()

    if not http then
        tab.status = "ошибка: модуль http не загружен"
        return
    end

    local ok, resp, err = pcall(http.get, u)
    if not ok then
        tab.status = "ошибка: " .. tostring(resp)
        return
    end
    if not resp then
        tab.status = "ошибка: " .. tostring(err)
        return
    end
    if resp.status and resp.status >= 400 then
        tab.status = "HTTP " .. tostring(resp.status)
    end

    tab.url = resp.finalUrl or u
    local body = resp.body or ""

    local dom
    if html and html.parse then
        local okP, res = pcall(html.parse, body)
        if okP then
            dom = res
        else
            dom = { type = "document", children = {
                { type = "text", text = body }
            }}
        end
    else
        dom = { type = "document", children = {
            { type = "text", text = body }
        }}
    end
    tab.dom = dom

    local g = layoutGeom()
    local contentW = g.w
    local boxes, total
    -- Применяем CSS (собираем <style> блоки + inline styles).
    local rulesList = {}
    if css and html and html.findAll then
        local styleNodes = html.findAll(dom, "style") or {}
        for _, sn in ipairs(styleNodes) do
            local txt = (html.getText and html.getText(sn)) or ""
            local okP, rules = pcall(css.parseStyleBlock, txt)
            if okP and rules then
                for _, r in ipairs(rules) do rulesList[#rulesList + 1] = r end
            end
        end
        pcall(css.apply, dom, rulesList)
    end
    local cssOpts = css and { rulesList = rulesList, inlineParser = css.parseInline } or nil

    if layout and layout.compute then
        local okL, lres = pcall(layout.compute, dom, contentW, { css = cssOpts, theme = THEME })
        if okL and lres then
            boxes = lres.boxes or lres
            total = lres.totalHeight or 0
        end
    end

    if not boxes then
        boxes = {}
        local y = 1
        for line in tostring(body):gmatch("([^\n]*)\n?") do
            if line ~= "" or y == 1 then
                table.insert(boxes, {
                    type = "text", x = 1, y = y, w = #line, h = 1, text = line,
                })
                y = y + 1
            end
        end
        total = y - 1
    end

    tab.boxes       = boxes
    tab.totalHeight = total or #boxes
    tab.scrollY     = 0
    tab.status      = "ok  (" .. #boxes .. " блоков, " ..
                      tostring(tab.totalHeight) .. " строк)"

    local title = extractTitle(dom) or tab.url
    tabs.setTitle(tab, title)

    -- Персистентная история посещений (если хранилище доступно).
    if bmstore and user and user.home and tab.url and tab.url ~= "" then
        pcall(bmstore.addHistory, user.home, tab.url, title)
    end

    appState.focus = "page"

    if tab.url and tab.url ~= "" then
        appState.urlInput = tab.url
        appState.cursorPos = #appState.urlInput + 1
    end

    if not opts.skipHistory then
        pushHistory(tab, tab.url or u)
    end
end

local function historyBack()
    local tab = currentTab()
    local h = tab.history
    if h.idx > 1 then
        h.idx = h.idx - 1
        navigate(h.stack[h.idx], { skipHistory = true })
    end
end

local function historyForward()
    local tab = currentTab()
    local h = tab.history
    if h.idx < #h.stack then
        h.idx = h.idx + 1
        navigate(h.stack[h.idx], { skipHistory = true })
    end
end

-- После смены активной вкладки — синхронизируем адрес-бар.
local function syncAddrFromTab()
    local tab = currentTab()
    appState.urlInput = tab.url or ""
    appState.cursorPos = #appState.urlInput + 1
end

-- ---------------------------------------------------------------
-- Закладки и специальные страницы
-- ---------------------------------------------------------------

local function htmlEscape(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub("\"", "&quot;")
    s = s:gsub("'", "&#39;")
    return s
end

-- Отрендерить произвольный HTML во внутреннюю вкладку (спец-страница).
local function openSpecialPage(content, pseudoUrl)
    local tab = currentTab()
    tab.url = pseudoUrl or "znatok://internal"
    local okP, dom = pcall(html.parse, content)
    if not okP or not dom then
        dom = { type = "document", children = {
            { type = "text", text = content or "" }
        }}
    end
    tab.dom = dom

    local g = layoutGeom()
    local contentW = g.w
    local boxes, total
    -- Применяем CSS (собираем <style> блоки + inline styles).
    local rulesList = {}
    if css and html and html.findAll then
        local styleNodes = html.findAll(dom, "style") or {}
        for _, sn in ipairs(styleNodes) do
            local txt = (html.getText and html.getText(sn)) or ""
            local okP, rules = pcall(css.parseStyleBlock, txt)
            if okP and rules then
                for _, r in ipairs(rules) do rulesList[#rulesList + 1] = r end
            end
        end
        pcall(css.apply, dom, rulesList)
    end
    local cssOpts = css and { rulesList = rulesList, inlineParser = css.parseInline } or nil

    if layout and layout.compute then
        local okL, lres = pcall(layout.compute, dom, contentW, { css = cssOpts, theme = THEME })
        if okL and lres then
            boxes = lres.boxes or lres
            total = lres.totalHeight or 0
        end
    end
    if not boxes then
        boxes = {}
        total = 0
    end
    tab.boxes = boxes
    tab.totalHeight = total or #boxes
    tab.scrollY = 0
    tab.status = "внутренняя страница"

    local title = extractTitle(dom) or "Закладки"
    tabs.setTitle(tab, title)

    appState.urlInput = tab.url
    appState.cursorPos = #appState.urlInput + 1
    appState.focus = "page"
end

local function renderBookmarksPage()
    local parts = { "<html><head><title>Закладки</title></head><body>" }
    parts[#parts + 1] = "<h1>Закладки</h1>"

    local bm = {}
    if bmstore and user and user.home then
        local ok, res = pcall(bmstore.loadBookmarks, user.home)
        if ok and type(res) == "table" then bm = res end
    end
    if #bm == 0 then
        parts[#parts + 1] = "<p>Закладок нет.</p>"
    else
        for _, b in ipairs(bm) do
            local u = htmlEscape(b.url or "")
            local t = htmlEscape(b.title or b.url or "")
            parts[#parts + 1] = '<p><a href="' .. u .. '">' .. t .. "</a></p>"
        end
    end

    parts[#parts + 1] = "<h2>История</h2>"
    local hist = {}
    if bmstore and user and user.home then
        local ok, res = pcall(bmstore.loadHistory, user.home)
        if ok and type(res) == "table" then hist = res end
    end
    if #hist == 0 then
        parts[#parts + 1] = "<p>История пуста.</p>"
    else
        local lim = math.min(50, #hist)
        for i = 1, lim do
            local h = hist[i]
            local u = htmlEscape(h.url or "")
            local t = htmlEscape(h.title or h.url or "")
            parts[#parts + 1] = '<p><a href="' .. u .. '">' .. t .. "</a></p>"
        end
    end

    parts[#parts + 1] = "</body></html>"
    return table.concat(parts)
end

local function toggleBookmark()
    local tab = currentTab()
    if not (bmstore and user and user.home) then
        tab.status = "закладки недоступны"
        return
    end
    local u = tab.url
    if not u or u == "" or u:sub(1, 9) == "znatok://" then
        tab.status = "нельзя добавить в закладки"
        return
    end
    local ok, isBm = pcall(bmstore.isBookmarked, user.home, u)
    if ok and isBm then
        pcall(bmstore.removeBookmark, user.home, u)
        tab.status = "Закладка удалена"
    else
        local title = tab.title or u
        pcall(bmstore.addBookmark, user.home, u, title)
        tab.status = "Закладка добавлена"
    end
end

local function openBookmarksPage()
    if not html or not layout then
        currentTab().status = "внутренние страницы недоступны"
        return
    end
    openSpecialPage(renderBookmarksPage(), "znatok://bookmarks")
end

-- ---------------------------------------------------------------
-- Ввод в адрес-баре
-- ---------------------------------------------------------------

local function addrInsert(ch)
    local cp = appState.cursorPos or (#appState.urlInput + 1)
    appState.urlInput = appState.urlInput:sub(1, cp - 1) .. ch .. appState.urlInput:sub(cp)
    appState.cursorPos = cp + #ch
end

local function addrBackspace()
    local cp = appState.cursorPos or (#appState.urlInput + 1)
    if cp > 1 then
        appState.urlInput = appState.urlInput:sub(1, cp - 2) .. appState.urlInput:sub(cp)
        appState.cursorPos = cp - 1
    end
end

local function addrDelete()
    local cp = appState.cursorPos or (#appState.urlInput + 1)
    if cp <= #appState.urlInput then
        appState.urlInput = appState.urlInput:sub(1, cp - 1) .. appState.urlInput:sub(cp + 1)
    end
end

-- ---------------------------------------------------------------
-- Скроллинг
-- ---------------------------------------------------------------

local function maxScroll()
    local g = layoutGeom()
    local vpH = g.contentY2 - g.contentY1 + 1
    local total = currentTab().totalHeight or 0
    return math.max(0, total - vpH)
end

local function scroll(delta)
    local tab = currentTab()
    local ns = (tab.scrollY or 0) + delta
    if ns < 0 then ns = 0 end
    local m = maxScroll()
    if ns > m then ns = m end
    tab.scrollY = ns
end

-- ---------------------------------------------------------------
-- Event loop
-- ---------------------------------------------------------------

local shiftDown = false

local function handleKey(k)
    if k == keys.escape then
        appState.running = false
        return
    end

    -- Модификаторы.
    if k == keys.leftAlt or k == keys.rightAlt then
        appState.altDown = true
        return
    end
    if k == keys.leftCtrl or k == keys.rightCtrl then
        appState.ctrlDown = true
        return
    end
    if k == keys.leftShift or k == keys.rightShift then
        shiftDown = true
        return
    end

    -- Ctrl-комбинации.
    if appState.ctrlDown then
        if k == keys.t then
            tabs.newTab(tabState, "")
            appState.urlInput = ""
            appState.cursorPos = 1
            appState.focus = "address"
            return
        elseif k == keys.w then
            tabs.closeTab(tabState, tabState.active)
            syncAddrFromTab()
            return
        elseif k == keys.tab then
            if shiftDown then
                tabs.prev(tabState)
            else
                tabs.next(tabState)
            end
            syncAddrFromTab()
            return
        elseif k == keys.d then
            toggleBookmark()
            return
        elseif k == keys.h then
            openBookmarksPage()
            return
        end
    end

    if k == keys.tab then
        appState.focus = (appState.focus == "address") and "page" or "address"
        return
    end

    -- Alt+Left/Right — история.
    if appState.altDown and k == keys.left then
        historyBack()
        return
    end
    if appState.altDown and k == keys.right then
        historyForward()
        return
    end

    if appState.focus == "address" then
        if k == keys.enter then
            navigate(appState.urlInput)
        elseif k == keys.backspace then
            addrBackspace()
        elseif k == keys.delete then
            addrDelete()
        elseif k == keys.left then
            appState.cursorPos = math.max(1, (appState.cursorPos or 1) - 1)
        elseif k == keys.right then
            appState.cursorPos = math.min(#appState.urlInput + 1, (appState.cursorPos or 1) + 1)
        elseif k == keys.home then
            appState.cursorPos = 1
        elseif k == keys["end"] then
            appState.cursorPos = #appState.urlInput + 1
        end
    else
        -- focus == "page"
        if k == keys.up then
            scroll(-1)
        elseif k == keys.down then
            scroll(1)
        elseif k == keys.pageUp then
            scroll(-10)
        elseif k == keys.pageDown then
            scroll(10)
        elseif k == keys.home then
            currentTab().scrollY = 0
        elseif k == keys["end"] then
            currentTab().scrollY = maxScroll()
        elseif k == keys.backspace then
            historyBack()
        end
    end
end

local function handleKeyUp(k)
    if k == keys.leftAlt or k == keys.rightAlt then
        appState.altDown = false
    end
    if k == keys.leftCtrl or k == keys.rightCtrl then
        appState.ctrlDown = false
    end
    if k == keys.leftShift or k == keys.rightShift then
        shiftDown = false
    end
end

local function handleChar(ch)
    if appState.ctrlDown then
        return
    end
    if appState.focus == "address" then
        addrInsert(ch)
    end
end

local function handleMouseClick(btn, x, y)
    local g = layoutGeom()

    -- Клик по tab-bar.
    if y == g.tabBarY then
        local z = tabs.hitBar(tabZones, x)
        if z then
            if z.type == "tab" then
                tabs.activate(tabState, z.idx)
                syncAddrFromTab()
            elseif z.type == "close" then
                tabs.closeTab(tabState, z.idx)
                syncAddrFromTab()
            elseif z.type == "new" then
                tabs.newTab(tabState, "")
                appState.urlInput = ""
                appState.cursorPos = 1
                appState.focus = "address"
            end
        end
        return
    end

    if y == g.addrY then
        if x >= g.goBtnX1 and x <= g.goBtnX2 + 1 then
            navigate(appState.urlInput)
        elseif x >= g.urlFieldX1 and x <= g.urlFieldX2 then
            appState.focus = "address"
            local fieldW = g.urlFieldX2 - g.urlFieldX1 + 1
            local offset = 0
            if #appState.urlInput > fieldW then offset = #appState.urlInput - fieldW end
            appState.cursorPos = math.min(#appState.urlInput + 1, (x - g.urlFieldX1 + 1) + offset)
        end
    elseif y >= g.contentY1 and y <= g.contentY2 then
        appState.focus = "page"
        local tab = currentTab()
        if not (tab.boxes and render and render.hitTest) then return end
        local viewport = {
            x = 1, y = g.contentY1,
            width = g.w, height = g.contentY2 - g.contentY1 + 1,
        }
        local box = render.hitTest(tab.boxes, x, y, tab.scrollY or 0, viewport)
        if not box then return end

        if box.type == "link" and box.href then
            if link and link.boxToAbsoluteUrl then
                local abs = link.boxToAbsoluteUrl(box, tab.url or "")
                if abs then
                    navigate(abs)
                else
                    tab.status = "не удалось разрешить ссылку: " .. tostring(box.href)
                end
            else
                navigate(box.href)
            end
        elseif box.type == "button" then
            local onclick = box.node and box.node.attrs and box.node.attrs.onclick
            if onclick and js and js.eval then
                local jsCtx = {
                    navigate = function(u) navigate(u) end,
                    submit = function(formId)
                        if not (form and form.submit and html and html.findAll) then return end
                        local forms = html.findAll(tab.dom, "form") or {}
                        for _, f in ipairs(forms) do
                            if f.attrs and f.attrs.id == formId then
                                local ok, resp = pcall(form.submit, f, tab.url, http, urlLib)
                                if ok and resp then
                                    if resp.finalUrl then
                                        navigate(resp.finalUrl)
                                    end
                                end
                                return
                            end
                        end
                    end,
                    alert = function(msg) tab.status = "alert: " .. tostring(msg) end,
                    back = historyBack,
                    forward = historyForward,
                }
                local ok, err = pcall(js.eval, onclick, jsCtx)
                if not ok then
                    tab.status = "js ошибка: " .. tostring(err)
                end
            else
                if form and form.submit and html and html.findAll then
                    local forms = html.findAll(tab.dom, "form") or {}
                    local function contains(node, target)
                        if node == target then return true end
                        if node.children then
                            for _, ch in ipairs(node.children) do
                                if contains(ch, target) then return true end
                            end
                        end
                        return false
                    end
                    local parentForm
                    for _, f in ipairs(forms) do
                        if box.node and contains(f, box.node) then
                            parentForm = f
                            break
                        end
                    end
                    if parentForm then
                        local ok, resp = pcall(form.submit, parentForm, tab.url, http, urlLib)
                        if ok and resp and resp.finalUrl then
                            navigate(resp.finalUrl)
                        elseif not ok then
                            tab.status = "ошибка отправки формы: " .. tostring(resp)
                        end
                    else
                        tab.status = "кнопка не связана с формой"
                    end
                end
            end
        elseif box.type == "input" then
            currentTab().status = "редактирование полей появится в следующей итерации"
        end
    end
end

local function handleMouseScroll(dir, x, y)
    local g = layoutGeom()
    if y >= g.contentY1 and y <= g.contentY2 then
        scroll(dir > 0 and 3 or -3)
    end
end

-- ---------------------------------------------------------------
-- Старт
-- ---------------------------------------------------------------

local function main()
    if not http or not render or not tabs then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.red)
        term.clear(); term.setCursorPos(1, 1)
        print("Браузер: не удалось загрузить модули из " .. appDir .. "/lib/")
        if not http   then print("  - http.lua")   end
        if not urlLib then print("  - url.lua")    end
        if not html   then print("  - html.lua")   end
        if not layout then print("  - layout.lua") end
        if not render then print("  - render.lua") end
        if not tabs   then print("  - tabs.lua")   end
        print("Нажмите любую клавишу для выхода.")
        os.pullEvent("key")
        return
    end

    redraw()
    while appState.running do
        local ev = { os.pullEvent() }
        local name = ev[1]
        if name == "key" then
            handleKey(ev[2])
        elseif name == "key_up" then
            handleKeyUp(ev[2])
        elseif name == "char" then
            handleChar(ev[2])
        elseif name == "mouse_click" then
            handleMouseClick(ev[2], ev[3], ev[4])
        elseif name == "mouse_scroll" then
            handleMouseScroll(ev[2], ev[3], ev[4])
        elseif name == "term_resize" then
            -- перерисуем
        end
        redraw()
    end

    term.setCursorBlink(false)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

main()
