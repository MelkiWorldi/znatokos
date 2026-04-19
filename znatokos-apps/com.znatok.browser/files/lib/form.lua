-- lib/form.lua
-- Подсистема HTML-форм для браузера ZnatokOS.
-- Собирает данные из DOM-формы, сериализует их и отправляет через httpLib.
-- Не требует require сторонних модулей — httpLib и urlLib прокидываются параметрами.
--
-- Формат нод совпадает с lib/html.lua:
--   { kind = "elem", tag = "...", attrs = {...}, children = {...} }
--   { kind = "text", text = "..." }
--
-- Экспорты: collect, submit, findFormForButton, setInputValue.

local M = {}

-- =========================================================================
-- Вспомогательные утилиты
-- =========================================================================

-- Безопасное чтение attrs.
local function attrs(node)
    if node and node.attrs then return node.attrs end
    return {}
end

-- Нижний регистр строки с защитой от nil.
local function lower(s)
    if type(s) ~= "string" then return "" end
    return s:lower()
end

-- Проверка на elem-ноду с заданным тегом.
local function isElem(node, tag)
    return type(node) == "table"
        and node.kind == "elem"
        and (tag == nil or node.tag == tag)
end

-- Обход дерева с колбэком. Если cb возвращает true — обход прекращается.
local function walk(node, cb)
    if not node then return false end
    if cb(node) then return true end
    if node.children then
        for _, ch in ipairs(node.children) do
            if walk(ch, cb) then return true end
        end
    end
    return false
end

-- Проверка: является ли needle потомком haystack (или им самим).
local function contains(haystack, needle)
    local found = false
    walk(haystack, function(n)
        if n == needle then
            found = true
            return true
        end
    end)
    return found
end

-- Собирает весь текстовый контент ноды (для textarea).
local function getText(node)
    if not node then return "" end
    local parts = {}
    local function rec(nd)
        if nd.kind == "text" then
            parts[#parts + 1] = nd.text or ""
        elseif nd.kind == "elem" and nd.children then
            for _, ch in ipairs(nd.children) do rec(ch) end
        end
    end
    rec(node)
    return table.concat(parts)
end

-- Проверка наличия булевого HTML-атрибута. Парсер из html.lua кладёт их как "".
local function hasAttr(node, name)
    local a = attrs(node)
    return a[name] ~= nil
end

-- =========================================================================
-- Обработка отдельных элементов формы
-- =========================================================================

-- Обработка <input>. Возвращает таблицу поля либо nil (поле пропускаем).
-- opts.submitButton — имя/value нажатой submit-кнопки.
local function processInput(node, opts)
    local a = attrs(node)
    local name = a.name
    if not name or name == "" then return nil end

    local itype = lower(a.type)
    if itype == "" then itype = "text" end

    local disabled = hasAttr(node, "disabled")

    -- file игнорируем — multipart не поддерживаем.
    if itype == "file" then return nil end

    -- reset и обычные button — никогда не отправляем.
    if itype == "reset" or itype == "button" then return nil end

    -- submit — только если это именно нажатая кнопка.
    if itype == "submit" or itype == "image" then
        local btn = opts and opts.submitButton
        if not btn then return nil end
        -- Сопоставление по имени или по значению.
        if btn == name or btn == (a.value or "") then
            return {
                name = name,
                value = a.value or "",
                type = itype,
                disabled = disabled,
            }
        end
        return nil
    end

    -- checkbox/radio — только если checked.
    if itype == "checkbox" or itype == "radio" then
        if not hasAttr(node, "checked") then return nil end
        -- Если value не указан, по стандарту используется "on".
        local val = a.value
        if val == nil or val == "" then val = "on" end
        return {
            name = name,
            value = val,
            type = itype,
            disabled = disabled,
        }
    end

    -- Обычные текстовые и подобные типы: text, email, password, hidden и т.п.
    return {
        name = name,
        value = a.value or "",
        type = itype,
        disabled = disabled,
    }
end

-- Обработка <textarea>. Значение — текст внутри.
local function processTextarea(node)
    local a = attrs(node)
    local name = a.name
    if not name or name == "" then return nil end
    return {
        name = name,
        value = getText(node),
        type = "textarea",
        disabled = hasAttr(node, "disabled"),
    }
end

-- Обработка <select>. Берём value выбранного <option>, или первого.
local function processSelect(node)
    local a = attrs(node)
    local name = a.name
    if not name or name == "" then return nil end

    local selectedVal
    local firstVal

    -- Рекурсивно проходим <option> (учитываем <optgroup>).
    local function scan(nd)
        if not nd.children then return end
        for _, ch in ipairs(nd.children) do
            if isElem(ch, "option") then
                local oa = attrs(ch)
                -- Если нет атрибута value — берём текст опции.
                local v = oa.value
                if v == nil then v = getText(ch) end
                if firstVal == nil then firstVal = v end
                if hasAttr(ch, "selected") and selectedVal == nil then
                    selectedVal = v
                end
            elseif isElem(ch, "optgroup") then
                scan(ch)
            end
        end
    end
    scan(node)

    local value = selectedVal
    if value == nil then value = firstVal end
    if value == nil then value = "" end

    return {
        name = name,
        value = value,
        type = "select",
        disabled = hasAttr(node, "disabled"),
    }
end

-- =========================================================================
-- Публичные экспорты
-- =========================================================================

-- Собирает состояние формы.
-- opts.submitButton — имя/value нажатой submit-кнопки (не обязательно).
function M.collect(formNode, opts)
    opts = opts or {}

    local result = {
        action = "",
        method = "GET",
        enctype = "application/x-www-form-urlencoded",
        fields = {},
    }

    if not isElem(formNode, "form") then
        return result
    end

    local fa = attrs(formNode)
    result.action = fa.action or ""
    result.method = (fa.method and fa.method ~= "" and fa.method:upper()) or "GET"
    result.enctype = (fa.enctype and fa.enctype ~= "" and fa.enctype)
        or "application/x-www-form-urlencoded"

    -- Обходим всё subtree формы и собираем поля.
    walk(formNode, function(n)
        if not isElem(n) then return end
        -- Саму ноду формы пропускаем.
        if n == formNode then return end
        local tag = n.tag
        local field
        if tag == "input" then
            field = processInput(n, opts)
        elseif tag == "textarea" then
            field = processTextarea(n)
        elseif tag == "select" then
            field = processSelect(n)
        end
        if field then
            result.fields[#result.fields + 1] = field
        end
    end)

    return result
end

-- Отправка формы.
-- baseUrl — текущий URL страницы (для резолвинга относительного action).
-- httpLib, urlLib — ссылки на lib/http и lib/url.
-- opts: { submitButton = optional }
function M.submit(formNode, baseUrl, httpLib, urlLib, opts)
    opts = opts or {}
    if not httpLib or not urlLib then
        return nil, "httpLib и urlLib обязательны"
    end
    if not isElem(formNode, "form") then
        return nil, "formNode не является <form>"
    end

    local data = M.collect(formNode, opts)

    -- multipart не поддерживаем.
    if lower(data.enctype):find("multipart", 1, true) then
        return nil, "multipart не поддерживается"
    end

    -- Собираем payload: пропускаем disabled и поля без имени.
    -- Массив { {k, v}, ... } превращаем в таблицу для queryBuild.
    local payload = {}
    for _, f in ipairs(data.fields) do
        if not f.disabled then
            -- Несколько полей с одинаковым именем: queryBuild принимает plain-таблицу
            -- (ключ → значение), поэтому последнее значение выигрывает. Для простоты
            -- отправляем последнее непустое — этого достаточно в рамках ТЗ.
            payload[f.name] = f.value
        end
    end

    -- Резолвим action относительно baseUrl. Пустой action = текущий URL.
    local actionUrl = data.action
    if actionUrl == nil or actionUrl == "" then
        actionUrl = baseUrl or ""
    else
        if urlLib.resolve and baseUrl then
            actionUrl = urlLib.resolve(baseUrl, actionUrl) or actionUrl
        end
    end
    if not actionUrl or actionUrl == "" then
        return nil, "нет action URL"
    end

    local method = data.method or "GET"

    if method == "GET" then
        -- Отрезаем существующий query из action и добавляем свой.
        -- queryBuild возвращает строку с префиксом "?" либо пустую.
        local qs = urlLib.queryBuild(payload)
        local base = actionUrl
        -- Если в actionUrl уже есть "?" — мы по простой схеме заменяем его целиком.
        -- Это соответствует поведению большинства браузеров для method="get".
        local qPos = base:find("?", 1, true)
        if qPos then base = base:sub(1, qPos - 1) end
        local finalUrl = base .. qs
        return httpLib.get(finalUrl)
    else
        -- POST (и любой другой метод трактуем как POST — CC не умеет иные).
        return httpLib.post(actionUrl, payload, { contentType = data.enctype })
    end
end

-- Находит ближайшую <form>, содержащую buttonNode.
-- Так как DOM без parent-ссылок, собираем все <form> и выбираем ту,
-- в subtree которой лежит buttonNode. Для вложенных форм (в живом HTML это редкость,
-- но возможно из-за «прощающего» парсера) выбираем самую глубокую.
function M.findFormForButton(domRoot, buttonNode)
    if not domRoot or not buttonNode then return nil end

    local forms = {}
    walk(domRoot, function(n)
        if isElem(n, "form") then forms[#forms + 1] = n end
    end)

    local bestForm
    local bestDepth = -1

    -- Для каждой формы считаем «глубину» нахождения кнопки — чем больше форм
    -- содержат кнопку, тем мы вложеннее. Достаточно просто проверять contains.
    for _, form in ipairs(forms) do
        if contains(form, buttonNode) then
            -- Используем количество форм, содержащих кнопку, как грубую метрику глубины.
            local depth = 0
            for _, other in ipairs(forms) do
                if other ~= form and contains(other, form) then
                    depth = depth + 1
                end
            end
            if depth > bestDepth then
                bestDepth = depth
                bestForm = form
            end
        end
    end

    return bestForm
end

-- Устанавливает значение input/textarea/checkbox/radio.
-- Мутирует ноду на месте.
function M.setInputValue(inputNode, newValue)
    if not isElem(inputNode) then return end
    inputNode.attrs = inputNode.attrs or {}
    local a = inputNode.attrs

    if inputNode.tag == "input" then
        local itype = lower(a.type)
        if itype == "checkbox" or itype == "radio" then
            -- newValue трактуется как boolean: переключаем атрибут checked.
            if newValue then
                a.checked = ""
            else
                a.checked = nil
            end
            return
        end
        -- Обычный input: просто пишем attrs.value.
        a.value = newValue == nil and "" or tostring(newValue)
        return
    end

    if inputNode.tag == "textarea" then
        local strVal = newValue == nil and "" or tostring(newValue)
        inputNode.children = inputNode.children or {}
        -- Ищем первый текстовый child.
        local firstText
        for _, ch in ipairs(inputNode.children) do
            if ch.kind == "text" then
                firstText = ch
                break
            end
        end
        if firstText then
            firstText.text = strVal
        else
            table.insert(inputNode.children, 1, { kind = "text", text = strVal })
        end
        return
    end

    if inputNode.tag == "select" then
        -- Помечаем selected нужный option; с остальных снимаем.
        local function scan(nd)
            if not nd.children then return end
            for _, ch in ipairs(nd.children) do
                if isElem(ch, "option") then
                    ch.attrs = ch.attrs or {}
                    local oa = ch.attrs
                    local v = oa.value
                    if v == nil then v = getText(ch) end
                    if v == newValue then
                        oa.selected = ""
                    else
                        oa.selected = nil
                    end
                elseif isElem(ch, "optgroup") then
                    scan(ch)
                end
            end
        end
        scan(inputNode)
        return
    end
end

return M
