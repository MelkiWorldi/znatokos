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

-- Кодировка ресурспака "CC:Tweaked Russian language" (Modrinth: KYJWaUcW).
-- Раскладка: А=191, Б=192, ..., Е=196, Ё=197, Ж=198, ..., Я=223,
-- а=224, ..., е=229, ё=230, ж=231, ..., ю=255, я=\13 (позиция CR).
local function codepointToCP1251(cp)
    if cp < 0x80 then return cp end
    -- Ё (уникод 0x0401) → 197
    if cp == 0x0401 then return 197 end
    -- ё (уникод 0x0451) → 230
    if cp == 0x0451 then return 230 end
    -- Заглавные А-Е (U+0410-0415) → 191-196
    if cp >= 0x0410 and cp <= 0x0415 then
        return cp - 0x0410 + 191
    end
    -- Заглавные Ж-Я (U+0416-042F) → 198-223
    if cp >= 0x0416 and cp <= 0x042F then
        return cp - 0x0416 + 198
    end
    -- Строчные а-е (U+0430-0435) → 224-229
    if cp >= 0x0430 and cp <= 0x0435 then
        return cp - 0x0430 + 224
    end
    -- Строчные ж-ю (U+0436-044E) → 231-255
    if cp >= 0x0436 and cp <= 0x044E then
        return cp - 0x0436 + 231
    end
    -- я (U+044F) → 13 (пакет использует позицию \r для "я")
    if cp == 0x044F then return 13 end
    -- ASCII-аналоги для символов без глифов в паке
    if cp == 0x00AB then return 0x3C end   -- « → <
    if cp == 0x00BB then return 0x3E end   -- » → >
    if cp == 0x2014 or cp == 0x2013 then return 0x2D end  -- — – → -
    if cp == 0x2022 then return 0x2A end   -- • → *
    if cp == 0x2026 then return 0x2E end   -- … → .
    if cp == 0x00A0 then return 0x20 end   -- non-breaking space
    if cp == 0x00D7 then return 0x78 end   -- × → x
    if cp == 0x2116 then return 0x23 end   -- № → #
    if cp == 0x2190 then return 0x3C end   -- ← → <
    if cp == 0x2191 then return 0x5E end   -- ↑ → ^
    if cp == 0x2192 then return 0x3E end   -- → → >
    if cp == 0x2193 then return 0x76 end   -- ↓ → v
    if cp == 0x2264 then return 0x3C end   -- ≤ → <
    if cp == 0x2265 then return 0x3E end   -- ≥ → >
    if cp == 0x2500 or cp == 0x2501 then return 0x2D end
    if cp == 0x2502 or cp == 0x2503 then return 0x7C end
    if cp >= 0x250C and cp <= 0x254B then return 0x2B end
    if cp == 0x2588 or cp == 0x25A0 then return 0x23 end   -- █ ■ → #
    if cp == 0x25CF then return 0x2A end                    -- ● → *
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
-- Re-entry guard: предотвращает двойное кодирование при вложенных вызовах.
-- term.write → origWrite → делегирует в wrapped w.write → БЕЗ guard'а
-- w.write закодировал бы повторно: CP1251-байты (0xC0..0xFF) интерпретируются
-- как битая UTF-8 → decodeUtf8 возвращает мусор → codepointToCP1251 даёт 0x3F = '?'.
local depth = 0
local function wrap(s) return M.encode(tostring(s)) end
local function safeWrap(s)
    if depth > 0 then return tostring(s) end
    return wrap(s)
end

local installed = false
function M.installHooks()
    if installed then return end
    installed = true

    local origWrite = term.write
    term.write = function(text)
        local s = safeWrap(text)
        depth = depth + 1
        local ok, err = pcall(origWrite, s)
        depth = depth - 1
        if not ok then error(err, 0) end
    end

    if term.blit then
        local origBlit = term.blit
        term.blit = function(text, fg, bg)
            local s = safeWrap(text)
            depth = depth + 1
            local ok, err = pcall(origBlit, s, fg, bg)
            depth = depth - 1
            if not ok then error(err, 0) end
        end
    end

    -- io.write: тоже через guard (возможно уходит в term.write внутри)
    local origIoWrite = io.write
    io.write = function(...)
        local parts = { ... }
        if depth == 0 then
            for i, v in ipairs(parts) do parts[i] = wrap(v) end
        end
        depth = depth + 1
        local ok, err = pcall(origIoWrite, table.unpack(parts))
        depth = depth - 1
        if not ok then error(err, 0) end
    end

    -- Оборачиваем window.create: w.write может вызываться напрямую
    -- (напр., kernel/window.lua рисует chrome через ch.write).
    if window and window.create then
        local origCreate = window.create
        window.create = function(...)
            local w = origCreate(...)
            local wWrite = w.write
            w.write = function(text)
                local s = safeWrap(text)
                depth = depth + 1
                local ok, err = pcall(wWrite, s)
                depth = depth - 1
                if not ok then error(err, 0) end
            end
            if w.blit then
                local wBlit = w.blit
                w.blit = function(text, fg, bg)
                    local s = safeWrap(text)
                    depth = depth + 1
                    local ok, err = pcall(wBlit, s, fg, bg)
                    depth = depth - 1
                    if not ok then error(err, 0) end
                end
            end
            return w
        end
    end
end

return M
