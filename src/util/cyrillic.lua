-- UTF-8 → Windows-1251 перекодировка для вывода в терминал CC: Tweaked.
-- Кириллица в исходниках хранится как UTF-8 (2 байта/символ),
-- но CC индексирует глифы по байту. Наш ресурспак располагает
-- кириллические глифы в позициях CP1251 (0xA8, 0xB8, 0xC0..0xFF).
-- Этот модуль перекодирует строки перед передачей в term.write.

local M = {}

-- Карта UTF-8 кода → байт CP1251.
-- Покрывает: А-Я, а-я, Ё, ё, а также знак № и ряд символов.
-- Кодпоинты русских букв: А=U+0410..Я=U+042F, а=U+0430..я=U+044F, Ё=U+0401, ё=U+0451.
-- В UTF-8:
--   А (U+0410) = 0xD0 0x90    — в CP1251: 0xC0
--   Я (U+042F) = 0xD0 0xAF    — в CP1251: 0xDF
--   а (U+0430) = 0xD0 0xB0    — в CP1251: 0xE0
--   п (U+043F) = 0xD0 0xBF    — в CP1251: 0xEF
--   р (U+0440) = 0xD1 0x80    — в CP1251: 0xF0
--   я (U+044F) = 0xD1 0x8F    — в CP1251: 0xFF
--   Ё (U+0401) = 0xD0 0x81    — в CP1251: 0xA8
--   ё (U+0451) = 0xD1 0x91    — в CP1251: 0xB8

local function decodeUtf8(s, i)
    local b = s:byte(i)
    if not b then return nil, i end
    if b < 0x80 then return b, i + 1 end
    if b >= 0xC2 and b <= 0xDF and i + 1 <= #s then
        local b2 = s:byte(i + 1)
        if b2 and b2 >= 0x80 and b2 <= 0xBF then
            return ((b - 0xC0) * 0x40) + (b2 - 0x80), i + 2
        end
    end
    if b >= 0xE0 and b <= 0xEF and i + 2 <= #s then
        local b2, b3 = s:byte(i + 1), s:byte(i + 2)
        return ((b - 0xE0) * 0x1000) + ((b2 - 0x80) * 0x40) + (b3 - 0x80), i + 3
    end
    -- некорректный байт — пропускаем
    return b, i + 1
end

local function codepointToCP1251(cp)
    if cp < 0x80 then return cp end
    if cp >= 0x0410 and cp <= 0x044F then return cp - 0x0410 + 0xC0 end
    if cp == 0x0401 then return 0xA8 end   -- Ё
    if cp == 0x0451 then return 0xB8 end   -- ё
    if cp == 0x2116 then return 0xB9 end   -- №
    if cp == 0x00AB then return 0xAB end   -- «
    if cp == 0x00BB then return 0xBB end   -- »
    if cp == 0x2014 then return 0x97 end   -- —
    if cp == 0x2013 then return 0x96 end   -- –
    if cp == 0x2022 then return 0x95 end   -- •
    if cp == 0x2026 then return 0x85 end   -- …
    if cp == 0x00A0 then return 0xA0 end   -- non-breaking space
    -- неизвестный символ
    return 0x3F                            -- "?"
end

function M.encode(s)
    if type(s) ~= "string" then return s end
    -- Быстрый путь: если в строке нет не-ASCII байтов, ничего не делаем
    local hasHi = false
    for i = 1, #s do
        if s:byte(i) >= 0x80 then hasHi = true; break end
    end
    if not hasHi then return s end

    local out = {}
    local i = 1
    while i <= #s do
        local cp, ni = decodeUtf8(s, i)
        if cp then out[#out + 1] = string.char(codepointToCP1251(cp)) end
        i = ni
    end
    return table.concat(out)
end

-- Устанавливает глобальные перехваты на вывод.
-- После вызова весь term.write / term.blit / print / io.write
-- перекодируют UTF-8 кириллицу в CP1251.
local installed = false
function M.installHooks()
    if installed then return end
    installed = true

    local origWrite = term.write
    term.write = function(text) return origWrite(M.encode(tostring(text))) end

    if term.blit then
        local origBlit = term.blit
        term.blit = function(text, fg, bg)
            return origBlit(M.encode(tostring(text)), fg, bg)
        end
    end

    -- io.write: оборачиваем только вывод в stdout
    local origIoWrite = io.write
    io.write = function(...)
        local parts = { ... }
        for i, v in ipairs(parts) do parts[i] = M.encode(tostring(v)) end
        return origIoWrite(table.unpack(parts))
    end

    -- print: Lua-реализация, чтобы не дублировать перевод через io.write
    -- (стандартный print вызывает term.write напрямую в некоторых сборках CC)
    local origPrint = print
    _G.print = function(...)
        local args = { ... }
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = M.encode(tostring(args[i]))
        end
        return origPrint(table.unpack(parts))
    end

    -- Также перехват window.write если окно уже создано — нельзя,
    -- поскольку window.create возвращает новую таблицу. Вместо этого
    -- оборачиваем window.create, чтобы каждое новое окно получало патч.
    if window and window.create then
        local origCreate = window.create
        window.create = function(...)
            local w = origCreate(...)
            local wWrite = w.write
            w.write = function(text) return wWrite(M.encode(tostring(text))) end
            if w.blit then
                local wBlit = w.blit
                w.blit = function(text, fg, bg)
                    return wBlit(M.encode(tostring(text)), fg, bg)
                end
            end
            return w
        end
    end
end

return M
