-- lib/layout.lua
-- Layout engine браузера ZnatokOS.
-- Превращает DOM (см. lib/html.lua) в плоский список боксов для рендера.
-- Самодостаточный: собственные реализации utf8Len и wrapWords, без зависимостей.
-- Входная нода: {kind="elem", tag=..., attrs={...}, children={...}} или {kind="text", text=...}.
-- Экспорт: M.compute(domRoot, widthChars, opts) -> {boxes=..., totalHeight=...}.

local M = {}

-- ============================================================================
--  Таблицы тегов
-- ============================================================================

-- Блочные теги: перенос строки до и после.
local BLOCK = {
    html=true, body=true, head=true, div=true, section=true, article=true,
    header=true, footer=true, nav=true, main=true, aside=true,
    h1=true, h2=true, h3=true, h4=true, h5=true, h6=true,
    p=true, ul=true, ol=true, li=true, hr=true,
    table=true, tr=true, form=true, pre=true, blockquote=true,
    dl=true, dt=true, dd=true, figure=true, figcaption=true,
}

-- Void-теги: не имеют children.
local VOID = {
    br=true, hr=true, img=true, input=true, meta=true, link=true,
    area=true, base=true, col=true, embed=true, source=true, track=true, wbr=true,
}

-- Игнорируемые теги: не выводим ни контент, ни детей.
local IGNORED = {
    script=true, style=true, head=true, meta=true, link=true,
    title=true, noscript=true,
}

-- Теги, внутри которых сохраняется форматирование (white-space: pre).
local PRE_TAGS = { pre=true }

-- ============================================================================
--  Цвета (fallback-таблица, если глобальный colors недоступен в тестах)
-- ============================================================================
local C = _G.colors or {
    white=1, orange=2, magenta=4, lightBlue=8, yellow=16, lime=32,
    pink=64, gray=128, lightGray=256, cyan=512, purple=1024, blue=2048,
    brown=4096, green=8192, red=16384, black=32768,
}

-- ============================================================================
--  UTF-8: длина строки в символах
-- ============================================================================
-- Считаем начальные байты UTF-8 (не 10xxxxxx).
local function utf8Len(s)
    if not s or s == "" then return 0 end
    local n = 0
    local i, len = 1, #s
    while i <= len do
        local b = s:byte(i)
        if b < 0x80 then i = i + 1
        elseif b < 0xC0 then i = i + 1       -- битый хвост, считаем как 1
        elseif b < 0xE0 then i = i + 2
        elseif b < 0xF0 then i = i + 3
        else i = i + 4 end
        n = n + 1
    end
    return n
end

-- Возвращает подстроку по символам (1-based, включительно).
local function utf8Sub(s, from, to)
    if not s or s == "" then return "" end
    local bytes = {}
    local i, len, idx = 1, #s, 1
    while i <= len do
        local b = s:byte(i)
        local step
        if b < 0x80 then step = 1
        elseif b < 0xC0 then step = 1
        elseif b < 0xE0 then step = 2
        elseif b < 0xF0 then step = 3
        else step = 4 end
        if idx >= from and (to == nil or idx <= to) then
            bytes[#bytes+1] = s:sub(i, i + step - 1)
        end
        idx = idx + 1
        i = i + step
        if to and idx > to then break end
    end
    return table.concat(bytes)
end

-- ============================================================================
--  Разбиение строки на слова и перенос по ширине
-- ============================================================================
-- Возвращает список токенов: слова и пробелы между ними (пробел как разделитель).
local function splitWords(text)
    local words = {}
    for w in text:gmatch("%S+") do
        words[#words+1] = w
    end
    return words
end

-- Перенос по словам. Возвращает список строк длиной не более width (в символах).
-- Если слово длиннее width, режем его жёстко по символам.
local function wrapWords(text, width, startCol)
    startCol = startCol or 1
    width = math.max(1, width)
    local lines = {}
    local cur = ""
    local curLen = 0
    local firstLineBudget = width - (startCol - 1)
    if firstLineBudget < 1 then
        -- Места в текущей строке не осталось — начинаем с новой строки.
        lines[#lines+1] = ""
        firstLineBudget = width
    end
    local budget = firstLineBudget

    local function flush()
        lines[#lines+1] = cur
        cur = ""
        curLen = 0
        budget = width
    end

    local words = splitWords(text)
    for _, w in ipairs(words) do
        local wl = utf8Len(w)
        if wl > budget and curLen == 0 then
            -- Слово длиннее оставшегося места. Если budget < width — попробуем
            -- перенести на новую строку целиком; иначе режем жёстко.
            if budget < width then
                flush()
            end
            if wl > width then
                -- Режем слово по символам на куски по width.
                local pos = 1
                while pos <= wl do
                    local chunk = utf8Sub(w, pos, pos + width - 1)
                    local cl = utf8Len(chunk)
                    if cl == budget and pos + cl - 1 < wl then
                        cur = chunk
                        curLen = cl
                        flush()
                    elseif cl < budget then
                        cur = chunk
                        curLen = cl
                        budget = budget - cl
                    else
                        cur = chunk
                        curLen = cl
                        flush()
                    end
                    pos = pos + cl
                end
            else
                cur = w
                curLen = wl
                budget = width - wl
            end
        else
            -- Нужен ли пробел перед словом
            local need = wl + (curLen > 0 and 1 or 0)
            if need > budget then
                flush()
                cur = w
                curLen = wl
                budget = width - wl
            else
                if curLen > 0 then
                    cur = cur .. " " .. w
                    curLen = curLen + 1 + wl
                    budget = budget - 1 - wl
                else
                    cur = w
                    curLen = wl
                    budget = budget - wl
                end
            end
        end
    end
    if curLen > 0 or #lines == 0 then
        lines[#lines+1] = cur
    end
    return lines
end

-- ============================================================================
--  Стили (hardcoded — CSS будет в iter 9)
-- ============================================================================
local function mergeStyle(base, extra)
    local s = {}
    if base then for k,v in pairs(base) do s[k] = v end end
    if extra then for k,v in pairs(extra) do s[k] = v end end
    return s
end

local function styleForTag(tag, base)
    if tag == "h1" then
        return mergeStyle(base, { fg = C.yellow, bold = true })
    elseif tag == "h2" or tag == "h3" or tag == "h4" or tag == "h5" or tag == "h6" then
        return mergeStyle(base, { fg = C.orange, bold = true })
    elseif tag == "b" or tag == "strong" then
        return mergeStyle(base, { fg = C.white, bold = true })
    elseif tag == "i" or tag == "em" then
        return mergeStyle(base, { fg = C.lightGray })
    elseif tag == "a" then
        return mergeStyle(base, { fg = C.lightBlue, underline = true })
    elseif tag == "code" or tag == "pre" then
        return mergeStyle(base, { fg = C.green })
    elseif tag == "del" or tag == "s" or tag == "strike" then
        return mergeStyle(base, { fg = C.lightGray, strike = true })
    elseif tag == "u" then
        return mergeStyle(base, { underline = true })
    elseif tag == "small" then
        return mergeStyle(base, { fg = C.lightGray })
    elseif tag == "blockquote" then
        return mergeStyle(base, { fg = C.lightGray })
    end
    return base
end

-- ============================================================================
--  Контекст walker
-- ============================================================================
-- ctx = {
--   cx, cy         — текущая позиция курсора (1-based)
--   width          — ширина viewport в символах
--   indent         — текущий отступ слева (символы)
--   style          — текущий computed style
--   boxes          — плоский массив боксов
--   inPre          — true, если мы внутри <pre> (white-space: pre)
--   link           — если мы внутри <a>, здесь {href=...}
--   listStack      — стек состояний списков: {{type="ul"|"ol", counter=N}, ...}
--   maxY           — максимально достигнутый y (для totalHeight)
-- }

local function newCtx(width, opts)
    opts = opts or {}
    local theme = opts.theme or {}
    return {
        cx = 1 + (opts.indent or 0),
        cy = 1,
        width = width,
        indent = opts.indent or 0,
        style = { fg = theme.fg or C.white, bg = theme.bg or C.black },
        boxes = {},
        inPre = false,
        link = nil,
        listStack = {},
        maxY = 1,
        -- CSS-контекст: { rulesList=..., inlineParser=function(str)->style }.
        -- Если nil — работает хардкод styleForTag (back-compat).
        css = opts.css,
    }
end

local function markY(ctx)
    if ctx.cy > ctx.maxY then ctx.maxY = ctx.cy end
end

-- Переход на новую строку (если мы не в её начале).
local function newline(ctx)
    if ctx.cx > 1 + ctx.indent then
        ctx.cy = ctx.cy + 1
        ctx.cx = 1 + ctx.indent
        markY(ctx)
    end
end

-- Жёсткий перенос (даже если строка пустая). Для <br>.
local function hardNewline(ctx)
    ctx.cy = ctx.cy + 1
    ctx.cx = 1 + ctx.indent
    markY(ctx)
end

-- ============================================================================
--  Эмиттеры боксов
-- ============================================================================
local function emitText(ctx, text, node)
    if not text or text == "" then return end
    local isLink = ctx.link ~= nil
    local boxType = isLink and "link" or "text"
    local box = {
        type = boxType,
        x = ctx.cx,
        y = ctx.cy,
        w = utf8Len(text),
        h = 1,
        text = text,
        node = node,
        style = { fg = ctx.style.fg, bg = ctx.style.bg,
                  bold = ctx.style.bold, underline = ctx.style.underline,
                  strike = ctx.style.strike },
    }
    if isLink then
        box.href = ctx.link.href
    end
    ctx.boxes[#ctx.boxes+1] = box
    ctx.cx = ctx.cx + utf8Len(text)
    markY(ctx)
end

-- Вставка текста с нормализацией пробелов и wrap.
local function pushText(ctx, rawText, node)
    if not rawText or rawText == "" then return end
    if ctx.inPre then
        -- Сохраняем переносы и пробелы как есть.
        local i = 1
        while i <= #rawText do
            local nl = rawText:find("\n", i, true)
            local line
            if nl then
                line = rawText:sub(i, nl - 1)
                -- Если строка помещается в width — emit как есть.
                if utf8Len(line) > 0 then
                    emitText(ctx, line, node)
                end
                hardNewline(ctx)
                i = nl + 1
            else
                line = rawText:sub(i)
                if utf8Len(line) > 0 then
                    emitText(ctx, line, node)
                end
                i = #rawText + 1
            end
        end
        return
    end

    -- Нормализуем whitespace: любая последовательность пробельных → один пробел.
    local normalized = rawText:gsub("[%s]+", " ")
    if normalized == " " then
        -- Одиночный пробел — просто продвинуть курсор, если он не в начале.
        if ctx.cx > 1 + ctx.indent and ctx.cx <= ctx.width then
            -- Ничего не эмитим, но помечаем что нужен ведущий пробел перед
            -- следующим словом. Для простоты — эмитим пробел как текст.
            emitText(ctx, " ", node)
        end
        return
    end

    local leadingSpace = normalized:sub(1,1) == " "
    local trailingSpace = normalized:sub(-1) == " "
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" then return end

    -- Если в начале был пробел и мы не в начале строки — добавим пробел.
    if leadingSpace and ctx.cx > 1 + ctx.indent then
        if ctx.cx < ctx.width then
            emitText(ctx, " ", node)
        end
    end

    local lines = wrapWords(normalized, ctx.width - ctx.indent, ctx.cx - ctx.indent)
    for i, line in ipairs(lines) do
        if i > 1 then
            hardNewline(ctx)
        end
        if line ~= "" then
            emitText(ctx, line, node)
        end
    end

    if trailingSpace and ctx.cx > 1 + ctx.indent and ctx.cx < ctx.width then
        emitText(ctx, " ", node)
    end
end

local function emitHr(ctx)
    newline(ctx)
    local w = ctx.width - ctx.indent
    local chars = {}
    for _ = 1, w do chars[#chars+1] = "-" end
    local box = {
        type = "hr",
        x = 1 + ctx.indent,
        y = ctx.cy,
        w = w,
        h = 1,
        text = table.concat(chars),
        node = nil,
        style = { fg = C.gray, bg = ctx.style.bg },
    }
    ctx.boxes[#ctx.boxes+1] = box
    ctx.cy = ctx.cy + 1
    ctx.cx = 1 + ctx.indent
    markY(ctx)
end

local function emitImg(ctx, node)
    local attrs = node.attrs or {}
    local src = attrs.src
    local alt = attrs.alt
    -- Если src указан — порождаем box type="image" (main.lua догрузит и отрисует).
    -- Иначе — текстовый плейсхолдер.
    if src and (src:match("%.nfp$") or src:match("%.nft$")) then
        -- Резервируем место под картинку. Реальные размеры выяснятся после http.get.
        -- Пока что задаём h=8 (средняя картинка), width=ctx.width (во всю строку).
        -- main.lua после загрузки пересчитает layout если размеры не совпали.
        local estH = tonumber(attrs.height) or 8
        local estW = tonumber(attrs.width)  or math.min(32, ctx.width)
        hardNewline(ctx)
        local box = {
            type = "image",
            x = ctx.cx, y = ctx.cy, w = estW, h = estH,
            src = src, alt = alt, node = node,
            style = { fg = C.white, bg = ctx.style.bg },
        }
        ctx.boxes[#ctx.boxes+1] = box
        for _ = 1, estH - 1 do hardNewline(ctx) end
        markY(ctx)
        hardNewline(ctx)
        return
    end
    -- Обычный placeholder
    local text = alt and ("[IMG: " .. alt .. "]") or "[IMG]"
    local w = utf8Len(text)
    if ctx.cx + w - 1 > ctx.width then
        hardNewline(ctx)
    end
    local box = {
        type = "img_placeholder",
        x = ctx.cx, y = ctx.cy, w = w, h = 1,
        text = text, node = node, alt = alt,
        style = { fg = C.cyan, bg = ctx.style.bg },
    }
    ctx.boxes[#ctx.boxes+1] = box
    ctx.cx = ctx.cx + w
    markY(ctx)
end

local function emitInput(ctx, node)
    local attrs = node.attrs or {}
    local inputType = attrs.type or "text"
    local value = attrs.value or ""
    local size = tonumber(attrs.size) or 16
    if inputType == "submit" or inputType == "button" then
        local label = value ~= "" and value or (attrs.name or "Submit")
        local text = "[ " .. label .. " ]"
        local w = utf8Len(text)
        if ctx.cx + w - 1 > ctx.width then hardNewline(ctx) end
        local box = {
            type = "button", x = ctx.cx, y = ctx.cy, w = w, h = 1,
            text = text, node = node,
            name = attrs.name, action = "submit",
            style = { fg = C.white, bg = C.gray },
        }
        ctx.boxes[#ctx.boxes+1] = box
        ctx.cx = ctx.cx + w
        markY(ctx)
        return
    end
    local padLen = math.max(0, size - utf8Len(value))
    local text = "[" .. value .. string.rep("_", padLen) .. "]"
    local w = utf8Len(text)
    if ctx.cx + w - 1 > ctx.width then hardNewline(ctx) end
    local box = {
        type = "input", x = ctx.cx, y = ctx.cy, w = w, h = 1,
        text = text, node = node,
        name = attrs.name, value = value, inputType = inputType,
        style = { fg = C.white, bg = C.gray },
    }
    ctx.boxes[#ctx.boxes+1] = box
    ctx.cx = ctx.cx + w
    markY(ctx)
end

-- Сбор всего текста внутри button (для label).
local function collectText(node)
    if node.kind == "text" then return node.text or "" end
    if node.kind == "elem" then
        local parts = {}
        for _, ch in ipairs(node.children or {}) do
            parts[#parts+1] = collectText(ch)
        end
        return table.concat(parts)
    end
    return ""
end

local function emitButton(ctx, node)
    local attrs = node.attrs or {}
    local label = collectText(node)
    label = label:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then label = attrs.value or "Button" end
    local text = "[ " .. label .. " ]"
    local w = utf8Len(text)
    if ctx.cx + w - 1 > ctx.width then hardNewline(ctx) end
    local box = {
        type = "button", x = ctx.cx, y = ctx.cy, w = w, h = 1,
        text = text, node = node,
        name = attrs.name, action = attrs.type or "button",
        style = { fg = C.white, bg = C.gray },
    }
    ctx.boxes[#ctx.boxes+1] = box
    ctx.cx = ctx.cx + w
    markY(ctx)
end

-- ============================================================================
--  Маркер <li>
-- ============================================================================
local function emitLiMarker(ctx)
    local top = ctx.listStack[#ctx.listStack]
    local marker
    if top and top.type == "ol" then
        top.counter = (top.counter or 0) + 1
        marker = tostring(top.counter) .. ". "
    else
        marker = "* "
    end
    emitText(ctx, marker, nil)
end

-- ============================================================================
--  Таблицы (очень упрощённо)
-- ============================================================================
-- Рендерим каждую строку таблицы как "cell | cell | cell".
-- Не пытаемся выравнивать столбцы.
local function renderTable(ctx, tableNode, walkNode)
    newline(ctx)
    -- Обходим rows вручную.
    local function walkRows(n)
        if n.kind ~= "elem" then return end
        if n.tag == "tr" then
            -- Для каждой ячейки — собрать текст и вывести через " | ".
            local cells = {}
            for _, ch in ipairs(n.children or {}) do
                if ch.kind == "elem" and (ch.tag == "td" or ch.tag == "th") then
                    local t = collectText(ch)
                    t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                    cells[#cells+1] = t
                end
            end
            newline(ctx)
            local line = table.concat(cells, " | ")
            pushText(ctx, line, n)
            newline(ctx)
        else
            for _, ch in ipairs(n.children or {}) do walkRows(ch) end
        end
    end
    walkRows(tableNode)
end

-- ============================================================================
--  Рекурсивный walker
-- ============================================================================
local function walkNode(node, ctx)
    if node == nil then return end

    if node.kind == "text" then
        pushText(ctx, node.text, node)
        return
    end

    if node.kind ~= "elem" then return end

    local tag = node.tag
    if IGNORED[tag] then return end

    -- <br>: жёсткий перенос строки.
    if tag == "br" then
        hardNewline(ctx)
        return
    end

    -- <hr>: горизонтальная линия.
    if tag == "hr" then
        emitHr(ctx)
        return
    end

    -- <img>: placeholder.
    if tag == "img" then
        emitImg(ctx, node)
        return
    end

    -- <input>: поле ввода.
    if tag == "input" then
        emitInput(ctx, node)
        return
    end

    -- <button>: кнопка (берёт текст из children).
    if tag == "button" then
        emitButton(ctx, node)
        return
    end

    -- <table>: упрощённый рендер.
    if tag == "table" then
        renderTable(ctx, node, walkNode)
        newline(ctx)
        return
    end

    -- Блочный? Перенос строки перед. Запоминаем y-начало для фоновой заливки.
    local blockStartY = nil
    if BLOCK[tag] then
        newline(ctx)
        blockStartY = ctx.cy
    end

    -- Списки: заведём стек.
    if tag == "ul" or tag == "ol" then
        ctx.listStack[#ctx.listStack+1] = { type = tag, counter = 0 }
    end

    -- <li>: маркер.
    if tag == "li" then
        emitLiMarker(ctx)
    end

    -- Сохраняем стиль и ссылку для восстановления.
    local savedStyle = ctx.style
    local savedLink = ctx.link
    local savedIndent = ctx.indent
    local savedInPre = ctx.inPre

    -- Определяем computed style для текущей ноды.
    -- Приоритет (низкий -> высокий):
    --   1) стиль предка (ctx.style)
    --   2) стиль от тега (hardcoded styleForTag) — только если CSS НЕ задан,
    --      либо если на ноде нет node.style (т.е. css.apply её не тронул)
    --   3) node.style — результат css.apply (правила из <style> блоков)
    --   4) inline style="..." (парсим через ctx.css.inlineParser)
    if ctx.css then
        -- CSS-режим: хардкод пропускаем, доверяем css.apply + inline.
        if node.style then
            ctx.style = mergeStyle(ctx.style, node.style)
        else
            -- Фолбэк на хардкод для тегов, которые css.apply не покрыл.
            ctx.style = styleForTag(tag, ctx.style)
        end
        local inlineRaw = node.attrs and node.attrs.style
        if inlineRaw and ctx.css.inlineParser then
            local ok, inlineStyle = pcall(ctx.css.inlineParser, inlineRaw)
            if ok and inlineStyle then
                ctx.style = mergeStyle(ctx.style, inlineStyle)
            end
        end
    else
        -- Back-compat: нет CSS — работает как раньше.
        ctx.style = styleForTag(tag, ctx.style)
    end

    if tag == "a" then
        local href = (node.attrs and node.attrs.href) or ""
        ctx.link = { href = href }
    end

    if PRE_TAGS[tag] then
        ctx.inPre = true
    end

    if tag == "blockquote" then
        ctx.indent = ctx.indent + 2
        ctx.cx = math.max(ctx.cx, 1 + ctx.indent)
    end

    -- Void-теги: детей не обрабатываем.
    if not VOID[tag] then
        for _, ch in ipairs(node.children or {}) do
            walkNode(ch, ctx)
        end
    end

    -- Фоновая заливка для блочных элементов с явным background.
    -- Добавляем box type="bg" ПЕРЕД остальными боксами этого блока в том же y-диапазоне.
    -- Реализация — append в конец; render.lua рисует bg-боксы первыми (отсортирует по z).
    if blockStartY and ctx.style and ctx.style.bg
       and savedStyle and ctx.style.bg ~= (savedStyle.bg or nil) then
        local blockEndY = ctx.cy
        if ctx.cx > 1 + ctx.indent then blockEndY = ctx.cy end
        if blockEndY >= blockStartY then
            ctx.boxes[#ctx.boxes+1] = {
                type = "bg",
                x = 1, y = blockStartY,
                w = ctx.width, h = blockEndY - blockStartY + 1,
                style = { bg = ctx.style.bg, fg = ctx.style.fg },
                _z = -1,   -- фон рисуется до контента
            }
        end
    end

    -- Восстановление.
    ctx.style = savedStyle
    ctx.link = savedLink
    ctx.indent = savedIndent
    ctx.inPre = savedInPre

    if tag == "ul" or tag == "ol" then
        ctx.listStack[#ctx.listStack] = nil
    end

    if BLOCK[tag] then
        newline(ctx)
    end
end

-- ============================================================================
--  Публичный API
-- ============================================================================
-- Строит layout. Возвращает { boxes = {...}, totalHeight = N }.
function M.compute(domRoot, widthChars, opts)
    opts = opts or {}
    local width = widthChars or 80
    local ctx = newCtx(width, opts)
    walkNode(domRoot, ctx)
    -- totalHeight — максимальный y, достигнутый в процессе.
    local h = ctx.maxY
    -- Если последний курсор ушёл дальше — учтём.
    if ctx.cy > h then h = ctx.cy end
    return { boxes = ctx.boxes, totalHeight = h }
end

-- Экспорт внутренних функций для тестов.
M._utf8Len = utf8Len
M._utf8Sub = utf8Sub
M._wrapWords = wrapWords

return M
