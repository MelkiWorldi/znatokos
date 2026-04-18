-- html.lua
-- Прощающий HTML-парсер для браузера ZnatokOS v0.3.0.
-- Строит DOM-дерево из строки. Рассчитан на реальный «грязный» HTML.
-- Lua 5.3, без внешних зависимостей.
--
-- Формат нод:
--   { kind = "elem", tag = "div", attrs = {...}, children = {...} }
--   { kind = "text", text = "..." }
--
-- Корень всегда: { kind = "elem", tag = "#document", attrs = {}, children = {...} }

local M = {}

-- =========================================================================
-- Таблицы-константы
-- =========================================================================

-- Элементы без содержимого (self-closing по природе).
local VOID = {
    area = true, base = true, br = true, col = true, embed = true,
    hr = true, img = true, input = true, keygen = true, link = true,
    meta = true, param = true, source = true, track = true, wbr = true,
}

-- «Сырые» элементы — их содержимое до закрывающего тега не парсится как HTML.
-- script/style — по стандарту. textarea/pre/code добавлены по ТЗ.
local RAW = {
    script = true, style = true, textarea = true,
    pre = true, code = true,
}

-- Таблица HTML-энтити (самые популярные; остальные — через числовые ссылки).
local ENTITIES = {
    amp = "&", lt = "<", gt = ">", quot = '"', apos = "'",
    nbsp = "\194\160",   -- UTF-8: U+00A0
    copy = "\194\169",   -- ©
    reg  = "\194\174",   -- ®
    trade = "\226\132\162", -- ™
    hellip = "\226\128\166", -- …
    mdash = "\226\128\148", -- —
    ndash = "\226\128\147", -- –
    lsquo = "\226\128\152", rsquo = "\226\128\153",
    ldquo = "\226\128\156", rdquo = "\226\128\157",
    laquo = "\194\171", raquo = "\194\187",
    middot = "\194\183",
}

-- Ограничения от злокачественного входа.
local MAX_DEPTH    = 200
local MAX_TAG_LEN  = 64

-- =========================================================================
-- Утилиты
-- =========================================================================

-- Кодирует codepoint в UTF-8 (для числовых entity).
local function utf8char(cp)
    if cp < 0 or cp > 0x10FFFF then return "?" end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40),
                           0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + (math.floor(cp / 0x40) % 0x40),
                           0x80 + (cp % 0x40))
    else
        return string.char(0xF0 + math.floor(cp / 0x40000),
                           0x80 + (math.floor(cp / 0x1000) % 0x40),
                           0x80 + (math.floor(cp / 0x40) % 0x40),
                           0x80 + (cp % 0x40))
    end
end

-- Декодирование одной entity (без ведущего &, без завершающей ;).
local function decode_one(name)
    if name:sub(1, 1) == "#" then
        local num
        if name:sub(2, 2) == "x" or name:sub(2, 2) == "X" then
            num = tonumber(name:sub(3), 16)
        else
            num = tonumber(name:sub(2), 10)
        end
        if num then return utf8char(num) end
        return nil
    end
    return ENTITIES[name]
end

-- Публичная функция: декодирует все entity в строке.
function M.decodeEntities(s)
    if not s or s == "" then return s end
    if not s:find("&", 1, true) then return s end

    local out = {}
    local i, n = 1, #s
    while i <= n do
        local amp = s:find("&", i, true)
        if not amp then
            out[#out + 1] = s:sub(i)
            break
        end
        if amp > i then
            out[#out + 1] = s:sub(i, amp - 1)
        end
        -- Ищем ; в пределах ~10 символов.
        local semi = s:find(";", amp + 1, true)
        if semi and semi - amp <= 10 then
            local name = s:sub(amp + 1, semi - 1)
            local rep = decode_one(name)
            if rep then
                out[#out + 1] = rep
                i = semi + 1
            else
                out[#out + 1] = "&"
                i = amp + 1
            end
        else
            out[#out + 1] = "&"
            i = amp + 1
        end
    end
    return table.concat(out)
end

-- Нижний регистр ASCII (быстро, без локали).
local function lower(s) return s:lower() end

-- =========================================================================
-- Парсер
-- =========================================================================

-- Проверка: может ли символ c (int из string.byte) быть частью имени тега.
-- HTML терпим: допускаем буквы, цифры, '-', '_', ':'.
local function is_name_char(c)
    return (c >= 0x41 and c <= 0x5A)   -- A-Z
        or (c >= 0x61 and c <= 0x7A)   -- a-z
        or (c >= 0x30 and c <= 0x39)   -- 0-9
        or c == 0x2D                   -- -
        or c == 0x5F                   -- _
        or c == 0x3A                   -- :
end

local function is_ws(c)
    return c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D or c == 0x0C
end

-- Добавляет текстовый кусок к children верхнего узла.
-- Склеивает подряд идущие text-ноды.
local function push_text(children, text)
    if text == "" then return end
    local last = children[#children]
    if last and last.kind == "text" then
        last.text = last.text .. text
    else
        children[#children + 1] = { kind = "text", text = text }
    end
end

-- Главная функция парсинга.
function M.parse(html)
    html = html or ""
    local root = { kind = "elem", tag = "#document", attrs = {}, children = {} }
    local stack = { root }   -- стек открытых элементов
    local i, n = 1, #html

    -- Буфер обычного текста (копим, чтобы не делать .. в цикле).
    local text_buf = {}

    local function flush_text()
        if #text_buf == 0 then return end
        local raw = table.concat(text_buf)
        text_buf = {}
        push_text(stack[#stack].children, M.decodeEntities(raw))
    end

    local function top() return stack[#stack] end

    -- Находит ближайший открытый тег с таким именем в стеке (индекс).
    local function find_open(tag)
        for k = #stack, 2, -1 do
            if stack[k].tag == tag then return k end
        end
        return nil
    end

    -- Закрывает элементы до (включая) указанного индекса в стеке.
    local function close_to(idx)
        while #stack >= idx do
            stack[#stack] = nil
        end
        if #stack == 0 then stack[1] = root end
    end

    -- Открывает новый элемент: кладёт в children текущего топа и в стек.
    local function open_elem(tag, attrs, self_closed)
        local node = { kind = "elem", tag = tag, attrs = attrs, children = {} }
        top().children[#top().children + 1] = node
        if self_closed or VOID[tag] then
            return node
        end
        if #stack >= MAX_DEPTH then
            -- Защита от переполнения: не углубляемся дальше.
            return node
        end
        stack[#stack + 1] = node
        return node
    end

    -- Парсер атрибутов. Возвращает таблицу атрибутов и индекс конца тега (>).
    -- start указывает на первый символ после имени тега.
    -- Также возвращает self_closed (true если был '/>').
    local function parse_attrs(start)
        local attrs = {}
        local p = start
        local self_closed = false
        while p <= n do
            local b = html:byte(p)
            -- Пропуск пробелов.
            while p <= n and is_ws(html:byte(p)) do p = p + 1 end
            if p > n then break end
            b = html:byte(p)
            if b == 0x3E then   -- '>'
                return attrs, p, self_closed
            end
            if b == 0x2F then   -- '/'
                self_closed = true
                p = p + 1
            else
                -- Читаем имя атрибута.
                local name_s = p
                while p <= n do
                    local cb = html:byte(p)
                    if cb == 0x3D or cb == 0x3E or cb == 0x2F or is_ws(cb) then
                        break
                    end
                    p = p + 1
                end
                if p == name_s then
                    -- Не удалось прочитать имя — пропускаем один символ.
                    p = p + 1
                else
                    local name = lower(html:sub(name_s, p - 1))
                    -- Пропуск пробелов между именем и '='.
                    while p <= n and is_ws(html:byte(p)) do p = p + 1 end
                    if p <= n and html:byte(p) == 0x3D then
                        -- есть '=', читаем значение
                        p = p + 1
                        while p <= n and is_ws(html:byte(p)) do p = p + 1 end
                        if p > n then
                            attrs[name] = ""
                            break
                        end
                        local qb = html:byte(p)
                        if qb == 0x22 or qb == 0x27 then   -- " или '
                            local quote = qb
                            local v_s = p + 1
                            p = v_s
                            while p <= n and html:byte(p) ~= quote do
                                p = p + 1
                            end
                            attrs[name] = M.decodeEntities(html:sub(v_s, p - 1))
                            if p <= n then p = p + 1 end   -- съесть закрывающую кавычку
                        else
                            -- Без кавычек: до пробела или '>'.
                            local v_s = p
                            while p <= n do
                                local cb = html:byte(p)
                                if is_ws(cb) or cb == 0x3E then break end
                                p = p + 1
                            end
                            attrs[name] = M.decodeEntities(html:sub(v_s, p - 1))
                        end
                    else
                        -- Булевый атрибут.
                        attrs[name] = ""
                    end
                end
            end
        end
        return attrs, p, self_closed
    end

    while i <= n do
        local b = html:byte(i)
        if b == 0x3C then   -- '<'
            -- Может быть: комментарий, doctype/CDATA, закрывающий тег, открывающий тег.
            local nb = html:byte(i + 1)
            if nb == 0x21 then   -- '<!'
                -- Комментарий или doctype.
                if html:sub(i + 2, i + 3) == "--" then
                    local close = html:find("-->", i + 4, true)
                    flush_text()
                    if close then
                        i = close + 3
                    else
                        i = n + 1   -- оборвано — конец ввода
                    end
                else
                    -- DOCTYPE, CDATA и прочее — пропускаем до '>'.
                    local close = html:find(">", i + 2, true)
                    flush_text()
                    if close then
                        i = close + 1
                    else
                        i = n + 1
                    end
                end
            elseif nb == 0x2F then   -- '</'
                -- Закрывающий тег.
                local name_s = i + 2
                local p = name_s
                while p <= n and is_name_char(html:byte(p) or 0) do
                    p = p + 1
                end
                if p == name_s or (p - name_s) > MAX_TAG_LEN then
                    -- Не имя — трактуем '<' как текст.
                    text_buf[#text_buf + 1] = "<"
                    i = i + 1
                else
                    local tag = lower(html:sub(name_s, p - 1))
                    -- Пропускаем до '>'.
                    while p <= n and html:byte(p) ~= 0x3E do p = p + 1 end
                    flush_text()
                    local idx = find_open(tag)
                    if idx then close_to(idx) end
                    if p <= n then i = p + 1 else i = n + 1 end
                end
            elseif nb and is_name_char(nb) then
                -- Открывающий тег.
                local name_s = i + 1
                local p = name_s
                while p <= n and is_name_char(html:byte(p) or 0) do
                    p = p + 1
                end
                if (p - name_s) == 0 or (p - name_s) > MAX_TAG_LEN then
                    text_buf[#text_buf + 1] = "<"
                    i = i + 1
                else
                    local tag = lower(html:sub(name_s, p - 1))
                    local attrs, end_p, self_closed = parse_attrs(p)
                    flush_text()

                    -- Авто-закрытие параграфа и прочие простые правила:
                    -- открыли <p> внутри <p> — закрываем предыдущий.
                    if tag == "p" and find_open("p") then
                        close_to(find_open("p"))
                    end
                    -- <li> внутри <li> — аналогично.
                    if tag == "li" and find_open("li") then
                        close_to(find_open("li"))
                    end

                    open_elem(tag, attrs, self_closed)

                    if end_p <= n then i = end_p + 1 else i = n + 1 end

                    -- Если это raw-элемент и не void/self-closed — читаем сырой текст
                    -- до соответствующего закрывающего тега.
                    if RAW[tag] and not self_closed and not VOID[tag] then
                        local lower_html = html   -- для поиска без регистра используем plain-find по lower
                        -- Ищем </tag> регистронезависимо: пробегом.
                        local close_from = i
                        local close_pos
                        local search_from = close_from
                        while true do
                            local lt = html:find("<", search_from, true)
                            if not lt then break end
                            if html:byte(lt + 1) == 0x2F then
                                local ns = lt + 2
                                local pe = ns
                                while pe <= n and is_name_char(html:byte(pe) or 0) do
                                    pe = pe + 1
                                end
                                local cand = lower(html:sub(ns, pe - 1))
                                if cand == tag then
                                    close_pos = lt
                                    break
                                end
                            end
                            search_from = lt + 1
                        end
                        local raw_text
                        if close_pos then
                            raw_text = html:sub(i, close_pos - 1)
                            -- Помещаем как text-child.
                            if raw_text ~= "" then
                                top().children[#top().children + 1] =
                                    { kind = "text", text = raw_text }
                            end
                            -- Сдвигаем i на позицию '<' и закрываем тег штатно.
                            -- Пропускаем </tag ...> до '>'.
                            local gt = html:find(">", close_pos + 2, true)
                            -- Закрываем: текущий топ — это raw-элемент.
                            close_to(#stack)
                            if gt then i = gt + 1 else i = n + 1 end
                        else
                            -- Закрывающего тега нет — берём всё до конца.
                            raw_text = html:sub(i)
                            if raw_text ~= "" then
                                top().children[#top().children + 1] =
                                    { kind = "text", text = raw_text }
                            end
                            close_to(#stack)
                            i = n + 1
                        end
                    end
                end
            else
                -- '<' без валидного продолжения — трактуем как текст.
                text_buf[#text_buf + 1] = "<"
                i = i + 1
            end
        else
            -- Обычный текст. Копим до следующего '<'.
            local lt = html:find("<", i, true)
            if lt then
                text_buf[#text_buf + 1] = html:sub(i, lt - 1)
                i = lt
            else
                text_buf[#text_buf + 1] = html:sub(i)
                i = n + 1
            end
        end
    end

    flush_text()
    -- Авто-закрытие всех оставшихся открытых элементов — они просто остаются
    -- в дереве как есть; стек сбрасывается.
    return root
end

-- =========================================================================
-- Обход дерева
-- =========================================================================

function M.findTag(node, tagName)
    if not node then return nil end
    tagName = tagName:lower()
    if node.kind == "elem" and node.tag == tagName then
        return node
    end
    if node.children then
        for _, ch in ipairs(node.children) do
            local f = M.findTag(ch, tagName)
            if f then return f end
        end
    end
    return nil
end

function M.findAll(node, tagName)
    local res = {}
    tagName = tagName:lower()
    local function walk(nd)
        if nd.kind == "elem" and nd.tag == tagName then
            res[#res + 1] = nd
        end
        if nd.children then
            for _, ch in ipairs(nd.children) do walk(ch) end
        end
    end
    if node then walk(node) end
    return res
end

function M.getText(node)
    if not node then return "" end
    local parts = {}
    local function walk(nd)
        if nd.kind == "text" then
            parts[#parts + 1] = nd.text
            return
        end
        if nd.kind == "elem" then
            if nd.tag == "script" or nd.tag == "style" then
                return
            end
            if nd.children then
                for _, ch in ipairs(nd.children) do walk(ch) end
            end
        end
    end
    walk(node)
    return table.concat(parts)
end

return M
