-- main.lua — скелет браузера ZnatokOS v0.3.0 (iter 7).
-- Возможности: адрес-бар, загрузка URL, рендер HTML, прокрутка.
-- НЕ реализовано пока: ссылки (клики), формы, JS, вкладки, закладки, история.

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

-- Пробрасываем url-модуль в link.lua (у link.lua нет require в CC).
if link and link._setUrlLib and urlLib then
    link._setUrlLib(urlLib)
end

-- ---------------------------------------------------------------
-- Состояние
-- ---------------------------------------------------------------

local state = {
    urlInput    = "http://85.239.37.114/store/index.json",
    cursorPos   = nil,       -- позиция курсора в адрес-баре
    currentUrl  = nil,
    dom         = nil,
    boxes       = nil,
    totalHeight = 0,
    scrollY     = 0,
    status      = "готов",
    focus       = "address", -- "address" | "page"
    running     = true,
    altDown     = false,
}
state.cursorPos = #state.urlInput + 1

-- История навигации.
local history = { stack = {}, idx = 0 }

local function pushHistory(u)
    -- Если мы не в конце истории (после back) — обрезаем будущее.
    while #history.stack > history.idx do
        table.remove(history.stack)
    end
    history.stack[#history.stack + 1] = u
    history.idx = #history.stack
end

local THEME = {
    bg          = colors.white,
    fg          = colors.black,
    chrome_bg   = colors.lightGray,
    chrome_fg   = colors.black,
    accent      = colors.blue,
    status_bg   = colors.gray,
    status_fg   = colors.white,
    link        = colors.blue,
}

-- ---------------------------------------------------------------
-- Геометрия
-- ---------------------------------------------------------------

local function layoutGeom()
    local w, h = term.getSize()
    return {
        w = w, h = h,
        addrY    = 1,
        sepY     = 2,
        contentY1 = 3,
        contentY2 = h - 1,
        statusY  = h,
        urlFieldX1 = 6,               -- после "URL: "
        urlFieldX2 = w - 6,           -- оставляем место на " [GO]"
        goBtnX1  = w - 4,
        goBtnX2  = w - 1,
    }
end

-- ---------------------------------------------------------------
-- Отрисовка
-- ---------------------------------------------------------------

local function drawChrome(g)
    -- Строка адреса.
    term.setBackgroundColor(THEME.chrome_bg)
    term.setTextColor(THEME.chrome_fg)
    term.setCursorPos(1, g.addrY)
    term.write(string.rep(" ", g.w))

    term.setCursorPos(1, g.addrY)
    term.write("URL: ")

    -- Поле ввода.
    local fieldW = g.urlFieldX2 - g.urlFieldX1 + 1
    term.setCursorPos(g.urlFieldX1, g.addrY)
    if state.focus == "address" then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    else
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.gray)
    end
    local shown = state.urlInput
    if #shown > fieldW then shown = shown:sub(-fieldW) end
    shown = shown .. string.rep(" ", math.max(0, fieldW - #shown))
    term.write(shown)

    -- Кнопка GO.
    term.setCursorPos(g.goBtnX1 - 1, g.addrY)
    term.setBackgroundColor(THEME.chrome_bg)
    term.setTextColor(THEME.chrome_fg)
    term.write(" ")
    term.setBackgroundColor(THEME.accent)
    term.setTextColor(colors.white)
    term.setCursorPos(g.goBtnX1, g.addrY)
    term.write("[GO]")

    -- Разделитель.
    term.setBackgroundColor(THEME.bg)
    term.setTextColor(colors.gray)
    term.setCursorPos(1, g.sepY)
    term.write(string.rep("-", g.w))
end

local function drawContent(g)
    local vpH = g.contentY2 - g.contentY1 + 1
    if vpH < 1 then return end

    if state.boxes and render then
        render.draw(nil, state.boxes, {
            x = 1, y = g.contentY1,
            width = g.w, height = vpH,
            scrollY = state.scrollY,
        }, { bg = THEME.bg, fg = THEME.fg })
    else
        -- Заглушка если боксов нет.
        term.setBackgroundColor(THEME.bg)
        term.setTextColor(colors.gray)
        for y = g.contentY1, g.contentY2 do
            term.setCursorPos(1, y)
            term.write(string.rep(" ", g.w))
        end
        term.setCursorPos(2, g.contentY1 + 1)
        term.write("Введите URL и нажмите Enter.")
        term.setCursorPos(2, g.contentY1 + 2)
        term.write("Tab — переключить фокус, стрелки — прокрутка.")
    end
end

local function drawStatus(g)
    term.setCursorPos(1, g.statusY)
    term.setBackgroundColor(THEME.status_bg)
    term.setTextColor(THEME.status_fg)
    -- Breadcrumb-индикатор истории.
    local crumb = ""
    if history.idx > 1 then crumb = crumb .. "<" else crumb = crumb .. " " end
    if history.idx < #history.stack then crumb = crumb .. ">" else crumb = crumb .. " " end
    local s = crumb .. " Статус: " .. tostring(state.status)
    if #s > g.w then s = s:sub(1, g.w) end
    s = s .. string.rep(" ", g.w - #s)
    term.write(s)
end

local function redraw()
    local g = layoutGeom()
    term.setBackgroundColor(THEME.bg)
    term.clear()
    drawChrome(g)
    drawContent(g)
    drawStatus(g)

    -- Курсор в адрес-баре.
    if state.focus == "address" then
        local fieldW = g.urlFieldX2 - g.urlFieldX1 + 1
        local text = state.urlInput
        local cp = state.cursorPos or (#text + 1)
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
-- Навигация
-- ---------------------------------------------------------------

local function navigate(u, opts)
    opts = opts or {}
    if not u or u == "" then
        state.status = "пустой URL"
        return
    end

    if urlLib and urlLib.isUrl and not urlLib.isUrl(u) then
        -- Попробуем добавить схему.
        u = "http://" .. u
    end

    state.status = "загрузка " .. u .. "..."
    redraw()

    if not http then
        state.status = "ошибка: модуль http не загружен"
        return
    end

    local ok, resp, err = pcall(http.get, u)
    if not ok then
        state.status = "ошибка: " .. tostring(resp)
        return
    end
    if not resp then
        state.status = "ошибка: " .. tostring(err)
        return
    end
    if resp.status and resp.status >= 400 then
        state.status = "HTTP " .. tostring(resp.status)
        -- Всё равно попробуем отрисовать тело.
    end

    state.currentUrl = resp.finalUrl or u
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
    state.dom = dom

    local g = layoutGeom()
    local contentW = g.w
    local boxes, total
    if layout and layout.compute then
        local okL, lres = pcall(layout.compute, dom, contentW, {})
        if okL and lres then
            boxes = lres.boxes or lres
            total = lres.totalHeight or 0
        end
    end

    if not boxes then
        -- Fallback: просто текст построчно.
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

    state.boxes       = boxes
    state.totalHeight = total or #boxes
    state.scrollY     = 0
    state.status      = "ok  (" .. #boxes .. " блоков, " ..
                        tostring(state.totalHeight) .. " строк)"
    state.focus       = "page"

    -- Обновляем поле адреса актуальным URL (после редиректов).
    if state.currentUrl then
        state.urlInput = state.currentUrl
        state.cursorPos = #state.urlInput + 1
    end

    if not opts.skipHistory then
        pushHistory(state.currentUrl or u)
    end
end

local function historyBack()
    if history.idx > 1 then
        history.idx = history.idx - 1
        navigate(history.stack[history.idx], { skipHistory = true })
    end
end

local function historyForward()
    if history.idx < #history.stack then
        history.idx = history.idx + 1
        navigate(history.stack[history.idx], { skipHistory = true })
    end
end

-- ---------------------------------------------------------------
-- Ввод в адрес-баре
-- ---------------------------------------------------------------

local function addrInsert(ch)
    local cp = state.cursorPos or (#state.urlInput + 1)
    state.urlInput = state.urlInput:sub(1, cp - 1) .. ch .. state.urlInput:sub(cp)
    state.cursorPos = cp + #ch
end

local function addrBackspace()
    local cp = state.cursorPos or (#state.urlInput + 1)
    if cp > 1 then
        state.urlInput = state.urlInput:sub(1, cp - 2) .. state.urlInput:sub(cp)
        state.cursorPos = cp - 1
    end
end

local function addrDelete()
    local cp = state.cursorPos or (#state.urlInput + 1)
    if cp <= #state.urlInput then
        state.urlInput = state.urlInput:sub(1, cp - 1) .. state.urlInput:sub(cp + 1)
    end
end

-- ---------------------------------------------------------------
-- Скроллинг
-- ---------------------------------------------------------------

local function maxScroll()
    local g = layoutGeom()
    local vpH = g.contentY2 - g.contentY1 + 1
    local total = state.totalHeight or 0
    return math.max(0, total - vpH)
end

local function scroll(delta)
    local ns = (state.scrollY or 0) + delta
    if ns < 0 then ns = 0 end
    local m = maxScroll()
    if ns > m then ns = m end
    state.scrollY = ns
end

-- ---------------------------------------------------------------
-- Event loop
-- ---------------------------------------------------------------

local function handleKey(k)
    if k == keys.escape then
        state.running = false
        return
    end

    -- Отслеживаем состояние Alt (CC:Tweaked шлёт отдельные key-события).
    if k == keys.leftAlt or k == keys.rightAlt then
        state.altDown = true
        return
    end

    if k == keys.tab then
        state.focus = (state.focus == "address") and "page" or "address"
        return
    end

    -- Alt+Left/Right — история (работает в любом фокусе).
    if state.altDown and k == keys.left then
        historyBack()
        return
    end
    if state.altDown and k == keys.right then
        historyForward()
        return
    end

    if state.focus == "address" then
        if k == keys.enter then
            navigate(state.urlInput)
        elseif k == keys.backspace then
            addrBackspace()
        elseif k == keys.delete then
            addrDelete()
        elseif k == keys.left then
            state.cursorPos = math.max(1, (state.cursorPos or 1) - 1)
        elseif k == keys.right then
            state.cursorPos = math.min(#state.urlInput + 1, (state.cursorPos or 1) + 1)
        elseif k == keys.home then
            state.cursorPos = 1
        elseif k == keys["end"] then
            state.cursorPos = #state.urlInput + 1
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
            state.scrollY = 0
        elseif k == keys["end"] then
            state.scrollY = maxScroll()
        elseif k == keys.backspace then
            -- Backspace в режиме страницы — назад по истории (как в старых браузерах).
            historyBack()
        end
    end
end

local function handleKeyUp(k)
    if k == keys.leftAlt or k == keys.rightAlt then
        state.altDown = false
    end
end

local function handleChar(ch)
    if state.focus == "address" then
        addrInsert(ch)
    end
end

local function handleMouseClick(btn, x, y)
    local g = layoutGeom()
    if y == g.addrY then
        if x >= g.goBtnX1 and x <= g.goBtnX2 + 1 then
            navigate(state.urlInput)
        elseif x >= g.urlFieldX1 and x <= g.urlFieldX2 then
            state.focus = "address"
            local fieldW = g.urlFieldX2 - g.urlFieldX1 + 1
            local offset = 0
            if #state.urlInput > fieldW then offset = #state.urlInput - fieldW end
            state.cursorPos = math.min(#state.urlInput + 1, (x - g.urlFieldX1 + 1) + offset)
        end
    elseif y >= g.contentY1 and y <= g.contentY2 then
        state.focus = "page"
        if not (state.boxes and render and render.hitTest) then return end
        local viewport = {
            x = 1, y = g.contentY1,
            width = g.w, height = g.contentY2 - g.contentY1 + 1,
        }
        local box = render.hitTest(state.boxes, x, y, state.scrollY or 0, viewport)
        if not box then return end

        if box.type == "link" and box.href then
            if link and link.boxToAbsoluteUrl then
                local abs = link.boxToAbsoluteUrl(box, state.currentUrl or "")
                if abs then
                    navigate(abs)
                else
                    state.status = "не удалось разрешить ссылку: " .. tostring(box.href)
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
                        local forms = html.findAll(state.dom, "form") or {}
                        for _, f in ipairs(forms) do
                            if f.attrs and f.attrs.id == formId then
                                local ok, resp = pcall(form.submit, f, state.currentUrl, http)
                                if ok and resp then
                                    -- Если пришёл finalUrl — идём на него как при обычной навигации.
                                    if resp.finalUrl then
                                        navigate(resp.finalUrl)
                                    end
                                end
                                return
                            end
                        end
                    end,
                    alert = function(msg) state.status = "alert: " .. tostring(msg) end,
                    back = historyBack,
                    forward = historyForward,
                }
                local ok, err = pcall(js.eval, onclick, jsCtx)
                if not ok then
                    state.status = "js ошибка: " .. tostring(err)
                end
            else
                -- Submit-кнопка формы: ищем ближайшую родительскую <form>, содержащую эту кнопку.
                if form and form.submit and html and html.findAll then
                    local forms = html.findAll(state.dom, "form") or {}
                    -- Ищем форму, в поддереве которой есть наш button node.
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
                        local ok, resp = pcall(form.submit, parentForm, state.currentUrl, http)
                        if ok and resp and resp.finalUrl then
                            navigate(resp.finalUrl)
                        elseif not ok then
                            state.status = "ошибка отправки формы: " .. tostring(resp)
                        end
                    else
                        state.status = "кнопка не связана с формой"
                    end
                end
            end
        elseif box.type == "input" then
            -- TODO (iter 10): инлайн-редактирование значения поля.
            state.status = "редактирование полей появится в следующей итерации"
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
    -- Проверка критических модулей.
    if not http or not render then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.red)
        term.clear(); term.setCursorPos(1, 1)
        print("Браузер: не удалось загрузить модули из " .. appDir .. "/lib/")
        if not http   then print("  - http.lua")   end
        if not urlLib then print("  - url.lua")    end
        if not html   then print("  - html.lua")   end
        if not layout then print("  - layout.lua") end
        if not render then print("  - render.lua") end
        print("Нажмите любую клавишу для выхода.")
        os.pullEvent("key")
        return
    end

    redraw()
    while state.running do
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
            -- ничего, просто перерисуем
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
