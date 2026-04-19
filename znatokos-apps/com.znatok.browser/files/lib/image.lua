-- lib/image.lua — загрузка и рендер картинок в браузере ZnatokOS.
--
-- Поддерживаемые форматы:
--   NFP (Nitrogen Fingers Paint) — текстовый пиксельный формат CC:Tweaked.
--     Каждый символ — один пиксель, hex-цифра 0..f = colors.*, пробел = прозрачный.
--     Размер 1 cell = 2 пикселя (верх/низ через blit с half-block).
--   NFT (Nitrogen Fingers Text) — текстовая раскраска с \30 \31 escape-последовательностями.
--
-- Экспорты:
--   image.fetch(url, httpLib) → imageData | nil, err
--   image.render(win, imgData, x, y)
--   image.fromString(s, type) → imgData  (для тестов)

local M = {}

-- NFP парсер
local function parseNFP(text)
    local rows = {}
    local maxW = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local row = {}
        for i = 1, #line do
            local ch = line:sub(i, i)
            if ch == " " then
                row[i] = nil  -- прозрачный
            else
                local n = tonumber(ch, 16)
                if n then
                    -- colors.* = bit mask (2^n). n=0 → white (2^0=1), n=15 → black (2^15=32768)
                    row[i] = bit32 and bit32.lshift(1, n) or (2 ^ n)
                end
            end
        end
        if #row > maxW then maxW = #row end
        rows[#rows + 1] = row
    end
    return { kind = "nfp", rows = rows, width = maxW, height = #rows }
end

-- Определение формата по URL или первым байтам
local function detectFormat(url, body)
    if url:lower():match("%.nfp$") then return "nfp" end
    if url:lower():match("%.nft$") then return "nft" end
    -- Fallback: если только hex-цифры и пробелы — NFP
    if body:sub(1, 100):match("^[%x ]*\n") then return "nfp" end
    return nil
end

-- Загрузка по HTTP
function M.fetch(url, httpLib)
    if not httpLib then return nil, "http unavailable" end
    local resp, err = httpLib.get(url)
    if not resp or not resp.body then return nil, err or "fetch failed" end
    local fmt = detectFormat(url, resp.body)
    if not fmt then return nil, "unknown image format" end
    if fmt == "nfp" then return parseNFP(resp.body) end
    return nil, "format " .. fmt .. " not implemented"
end

function M.fromString(s, fmt)
    if fmt == "nfp" or fmt == nil then return parseNFP(s) end
    return nil
end

-- Отрисовка. win = term (или nil = текущий редирект).
-- Используем "полупиксельный" рендер: 2 вертикальных пикселя → 1 cell через blit.
-- Верхний пиксель = bg char ' ' с bg=topColor, нижний реализуем как... увы,
-- CC не умеет half-blocks без custom font. Поэтому упрощённо:
-- 1 ряд NFP = 1 ряд в терминале. Пиксель = bg-закрашенный пробел.
function M.render(win, img, x, y)
    win = win or term
    if not img or img.kind ~= "nfp" then return end
    for row = 1, img.height do
        local rowData = img.rows[row] or {}
        win.setCursorPos(x, y + row - 1)
        for col = 1, img.width do
            local c = rowData[col]
            if c then
                win.setBackgroundColor(c)
                win.write(" ")
            else
                -- прозрачный пропуск — курсор сдвигаем вручную
                local cx, cy = win.getCursorPos()
                win.setCursorPos(cx + 1, cy)
            end
        end
    end
end

return M
