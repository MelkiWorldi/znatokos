-- UTF-8 / CP1251 aware текстовые утилиты.
-- Строки в исходниках ЗнатокOS — UTF-8. Перед выводом проходят через
-- util/cyrillic → CP1251. Для ДЛИНЫ И ВЁРСТКИ нам нужны символы, не байты.
local M = {}

-- Количество символов в UTF-8 строке (не байт).
function M.len(s)
    if type(s) ~= "string" then return 0 end
    local n, i = 0, 1
    while i <= #s do
        local b = s:byte(i)
        if b < 0x80 then i = i + 1
        elseif b < 0xC0 then i = i + 1 -- битый байт — шаг
        elseif b < 0xE0 then i = i + 2
        elseif b < 0xF0 then i = i + 3
        else i = i + 4 end
        n = n + 1
    end
    return n
end

-- Вернуть подстроку по символам (1-indexed, включительно).
function M.sub(s, i, j)
    if type(s) ~= "string" then return "" end
    j = j or M.len(s)
    local chars = {}
    local pos = 1
    while pos <= #s do
        local b = s:byte(pos)
        local step
        if b < 0x80 then step = 1
        elseif b < 0xC0 then step = 1
        elseif b < 0xE0 then step = 2
        elseif b < 0xF0 then step = 3
        else step = 4 end
        chars[#chars + 1] = s:sub(pos, pos + step - 1)
        pos = pos + step
    end
    if i < 0 then i = math.max(1, #chars + i + 1) end
    if j < 0 then j = #chars + j + 1 end
    i = math.max(1, i); j = math.min(#chars, j)
    if j < i then return "" end
    return table.concat(chars, "", i, j)
end

-- Разбить s на символы в массив.
function M.chars(s)
    if type(s) ~= "string" then return {} end
    local out, pos = {}, 1
    while pos <= #s do
        local b = s:byte(pos)
        local step
        if b < 0x80 then step = 1
        elseif b < 0xC0 then step = 1
        elseif b < 0xE0 then step = 2
        elseif b < 0xF0 then step = 3
        else step = 4 end
        out[#out + 1] = s:sub(pos, pos + step - 1)
        pos = pos + step
    end
    return out
end

-- Перенос по словам. Возвращает массив строк, каждая длиной ≤ width символов.
function M.wrap(s, width)
    if width < 1 then return { s } end
    local out = {}
    -- Разбиваем по \n сначала
    for paragraph in (s .. "\n"):gmatch("([^\n]*)\n") do
        if paragraph == "" then
            out[#out + 1] = ""
        else
            local line = ""
            local lineLen = 0
            for word in paragraph:gmatch("%S+") do
                local wLen = M.len(word)
                if lineLen == 0 then
                    -- первое слово в строке; если слово длиннее width — режем
                    if wLen <= width then
                        line = word; lineLen = wLen
                    else
                        -- долго — разбиваем посимвольно
                        for i = 1, wLen, width do
                            out[#out + 1] = M.sub(word, i, i + width - 1)
                        end
                        line = ""; lineLen = 0
                    end
                else
                    if lineLen + 1 + wLen <= width then
                        line = line .. " " .. word
                        lineLen = lineLen + 1 + wLen
                    else
                        out[#out + 1] = line
                        if wLen <= width then
                            line = word; lineLen = wLen
                        else
                            for i = 1, wLen, width do
                                out[#out + 1] = M.sub(word, i, i + width - 1)
                            end
                            line = ""; lineLen = 0
                        end
                    end
                end
            end
            if lineLen > 0 then out[#out + 1] = line end
        end
    end
    return out
end

-- Обрезать строку до width символов, если длиннее — добавить ellipsis.
function M.ellipsize(s, width)
    if M.len(s) <= width then return s end
    if width <= 1 then return M.sub(s, 1, width) end
    return M.sub(s, 1, width - 1) .. "…"
end

-- Дополнить пробелами до width символов (для колонок).
function M.pad(s, width, align)
    local l = M.len(s)
    if l >= width then return M.sub(s, 1, width) end
    local diff = width - l
    if align == "right" then
        return string.rep(" ", diff) .. s
    elseif align == "center" then
        local left = math.floor(diff / 2)
        return string.rep(" ", left) .. s .. string.rep(" ", diff - left)
    else
        return s .. string.rep(" ", diff)
    end
end

-- Центрировать строку в заданной ширине.
function M.center(s, width)
    return M.pad(s, width, "center")
end

return M
