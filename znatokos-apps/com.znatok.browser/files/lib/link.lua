-- lib/link.lua
-- Утилиты для работы со ссылками в браузере ZnatokOS.
-- Зависит от url.lua (получает его через loader-функцию, либо через require).

local M = {}

-- Внутренний загрузчик url.lua.
-- Пытается require("url"); если не получилось — рассчитывает, что вызывающий
-- передаст url-модуль через M._setUrlLib.
local urlLib = nil
local function getUrlLib()
    if urlLib then return urlLib end
    local ok, mod = pcall(require, "url")
    if ok and mod then
        urlLib = mod
        return urlLib
    end
    return nil
end

-- Позволяет вручную установить модуль url (из main.lua, где используется loadfile).
function M._setUrlLib(mod)
    urlLib = mod
end

-- Превращает относительный href из linkBox в абсолютный URL.
-- @param linkBox table  бокс типа "link" из layout.compute; должен иметь .href.
-- @param baseUrl string текущий URL страницы (для резолва относительных ссылок).
-- @return string|nil   абсолютный URL или nil, если href пустой.
function M.boxToAbsoluteUrl(linkBox, baseUrl)
    if type(linkBox) ~= "table" then return nil end
    local href = linkBox.href
    if type(href) ~= "string" or href == "" then return nil end

    local u = getUrlLib()
    if u and u.resolve and baseUrl and baseUrl ~= "" then
        local ok, res = pcall(u.resolve, baseUrl, href)
        if ok and res then return res end
    end
    -- Фолбек: возвращаем href как есть.
    return href
end

-- Собирает все уникальные ссылки на странице.
-- @param boxes  массив боксов из layout.compute.
-- @return массив { {box = <box>, href = <string>}, ... } — по одному на уникальный href.
function M.collectLinks(boxes)
    local result = {}
    if type(boxes) ~= "table" then return result end
    local seen = {}
    for _, b in ipairs(boxes) do
        if b.type == "link" and type(b.href) == "string" and b.href ~= "" then
            if not seen[b.href] then
                seen[b.href] = true
                result[#result + 1] = { box = b, href = b.href }
            end
        end
    end
    return result
end

return M
