-- tabs.lua — модель и UI вкладок браузера ZnatokOS.
-- Вкладка = одна страница со своим DOM, layout, scroll и историей.

local M = {}

-- ---------------------------------------------------------------
-- Модель
-- ---------------------------------------------------------------

local function newEmptyTab(id, url)
    return {
        id          = id,
        url         = url or "",
        title       = "Новая вкладка",
        dom         = nil,
        boxes       = nil,
        totalHeight = 0,
        scrollY     = 0,
        status      = "готов",
        history     = { stack = {}, idx = 0 },
    }
end

function M.newState()
    local t = newEmptyTab(1, "")
    return {
        tabs    = { t },
        active  = 1,
        nextId  = 2,
    }
end

function M.newTab(state, url)
    local t = newEmptyTab(state.nextId, url or "")
    state.nextId = state.nextId + 1
    table.insert(state.tabs, t)
    state.active = #state.tabs
    return t
end

function M.closeTab(state, idx)
    if not idx or idx < 1 or idx > #state.tabs then return end
    table.remove(state.tabs, idx)
    if #state.tabs == 0 then
        -- Всегда остаётся минимум одна вкладка.
        local t = newEmptyTab(state.nextId, "")
        state.nextId = state.nextId + 1
        table.insert(state.tabs, t)
        state.active = 1
        return
    end
    if state.active > #state.tabs then
        state.active = #state.tabs
    elseif state.active >= idx and state.active > 1 then
        -- если закрыли раньше активной — активная "съехала" на -1
        if idx < state.active then
            state.active = state.active - 1
        end
        -- если idx == state.active — активной станет та же позиция (следующая вкладка)
    end
    if state.active < 1 then state.active = 1 end
end

function M.activate(state, idx)
    if idx and idx >= 1 and idx <= #state.tabs then
        state.active = idx
    end
end

function M.current(state)
    return state.tabs[state.active]
end

function M.next(state)
    if #state.tabs == 0 then return end
    state.active = (state.active % #state.tabs) + 1
end

function M.prev(state)
    if #state.tabs == 0 then return end
    state.active = state.active - 1
    if state.active < 1 then state.active = #state.tabs end
end

function M.setTitle(tab, title)
    if not tab then return end
    if title and title ~= "" then
        tab.title = title
    end
end

-- ---------------------------------------------------------------
-- Отрисовка tab-bar
-- ---------------------------------------------------------------

local MAX_TITLE = 15

local function ellipsize(s, maxW)
    if not s then return "" end
    if #s <= maxW then return s end
    if maxW <= 1 then return s:sub(1, maxW) end
    return s:sub(1, maxW - 1) .. "…"
end

local function titleOf(tab)
    local t = tab.title
    if not t or t == "" then
        t = (tab.url and tab.url ~= "") and tab.url or "Новая вкладка"
    end
    return t
end

-- Рисует tab-bar на одной строке.
-- Формат каждой вкладки:
--   активная:   [ title × ]
--   неактивная: [ title ]
-- Справа: [+]
-- Если не помещается — в конце появляется "... N" с количеством скрытых.
-- Возвращает массив зон: {type, idx, x1, x2}.
function M.renderBar(win, state, opts)
    opts = opts or {}
    local y     = opts.y or 1
    local width = opts.width
    local theme = opts.theme or {}

    local active_fg   = theme.active_fg   or colors.black
    local active_bg   = theme.active_bg   or colors.white
    local inactive_fg = theme.inactive_fg or colors.black
    local inactive_bg = theme.inactive_bg or colors.lightGray
    local accent      = theme.accent      or colors.blue

    if not width then
        local w = win.getSize and select(1, win.getSize()) or 51
        width = w
    end

    -- Сначала фон.
    win.setBackgroundColor(inactive_bg)
    win.setTextColor(inactive_fg)
    win.setCursorPos(1, y)
    win.write(string.rep(" ", width))

    local zones = {}
    local newBtn = "[+]"
    local newBtnW = #newBtn
    -- резерв под [+] (пробел + 3 символа)
    local reservedRight = newBtnW + 1

    -- Сначала посчитаем, сколько вкладок поместится целиком.
    -- Длина вкладки:
    --   активная:   1(sep) + 1( ) + title + 1( ) + 1(×) + 1( ) = title+5, потом sep
    --   неактивная: 1(sep) + 1( ) + title + 1( ) + 1( ) = title+4
    -- Используем общий формат: "[ title ]" = title+4, активная добавляет "×" -> title+5.
    local function tabWidth(tab, isActive)
        local t = ellipsize(titleOf(tab), MAX_TITLE)
        if isActive then
            return #t + 5  -- "[ title × ]"... нет, считаем: "[", " ", title, " ", "×", "]" = len+4 символа границ
        else
            return #t + 4  -- "[", " ", title, " ", "]"
        end
    end
    -- Пересчитаем точнее:
    -- "[ " + title + " ]" = 2 + len + 2 = len+4
    -- "[ " + title + " × ]" = 2 + len + 3 = len+5  (пробел, ×, пробел, ])... нет
    -- Формат активной: "[ title × ]" => '[' ' ' title ' ' '×' ' ' ']' = 6 + len. Упростим: делаем без финального пробела.
    -- Остановимся на: активная "[ title ×]" = len + 5, неактивная "[ title ]" = len + 4.

    -- Определим, сколько вкладок можно показать.
    local avail = width - reservedRight
    local shownCount = #state.tabs
    local widths = {}
    local totalW = 0
    for i, tab in ipairs(state.tabs) do
        widths[i] = tabWidth(tab, i == state.active)
        totalW = totalW + widths[i]
    end

    -- Если всё помещается — рисуем все. Иначе уменьшаем shownCount, добавляя место под "... N".
    local hidden = 0
    if totalW > avail then
        -- Нужно показывать "... N" (занимает, например, 6 символов: "... 99")
        local ellW = 6
        while shownCount > 1 and (totalW + ellW) > avail do
            totalW = totalW - widths[shownCount]
            shownCount = shownCount - 1
        end
        hidden = #state.tabs - shownCount
    end

    -- Рисуем вкладки.
    local x = 1
    for i = 1, shownCount do
        local tab = state.tabs[i]
        local isActive = (i == state.active)
        local t = ellipsize(titleOf(tab), MAX_TITLE)

        if isActive then
            win.setBackgroundColor(active_bg)
            win.setTextColor(active_fg)
        else
            win.setBackgroundColor(inactive_bg)
            win.setTextColor(inactive_fg)
        end

        local x1 = x
        win.setCursorPos(x, y)
        if isActive then
            -- "[ title " + "×" + "]"
            win.write("[ " .. t .. " ")
            local closeX = x + 2 + #t + 1 - 1  -- позиция "×"... проще: после "[ title " идёт "×"
            -- пересчитаем: "[", " ", t (len), " "  -> позиция × = x + 2 + len + 1 = x + len + 3
            closeX = x + #t + 3
            win.setTextColor(accent)
            win.write("×")
            win.setTextColor(active_fg)
            win.write("]")
            local x2 = x + widths[i] - 1
            table.insert(zones, { type = "tab",   idx = i, x1 = x1, x2 = x2 })
            table.insert(zones, { type = "close", idx = i, x1 = closeX, x2 = closeX })
            x = x2 + 1
        else
            win.write("[ " .. t .. " ]")
            local x2 = x + widths[i] - 1
            table.insert(zones, { type = "tab", idx = i, x1 = x1, x2 = x2 })
            x = x2 + 1
        end
    end

    -- "... N" если есть скрытые.
    if hidden > 0 then
        win.setBackgroundColor(inactive_bg)
        win.setTextColor(inactive_fg)
        win.setCursorPos(x, y)
        local s = "... " .. tostring(hidden)
        win.write(s)
        x = x + #s
    end

    -- [+] справа.
    local newX1 = width - newBtnW + 1
    win.setBackgroundColor(inactive_bg)
    win.setTextColor(accent)
    win.setCursorPos(newX1, y)
    win.write(newBtn)
    table.insert(zones, { type = "new", idx = 0, x1 = newX1, x2 = width })

    return zones
end

function M.hitBar(zones, clickX)
    if not zones then return nil end
    -- Приоритет: close перед tab (close попадает в координату tab тоже).
    local tabHit
    for _, z in ipairs(zones) do
        if clickX >= z.x1 and clickX <= z.x2 then
            if z.type == "close" or z.type == "new" then
                return z
            elseif z.type == "tab" then
                tabHit = z
            end
        end
    end
    return tabHit
end

return M
