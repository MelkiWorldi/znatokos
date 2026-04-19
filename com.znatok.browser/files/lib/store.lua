-- store.lua — персистентное хранилище закладок и истории для ZnatokOS Browser.
-- Работает через глобальный `fs` (sandbox предоставляет его при наличии fs.home).
-- Файлы:
--   <userHome>/.browser/bookmarks.json
--   <userHome>/.browser/history.json

local M = {}

local MAX_HISTORY = 500

-- ---------------------------------------------------------------
-- Вспомогательные: сериализация
-- ---------------------------------------------------------------

local function encode(data)
    if textutils and textutils.serializeJSON then
        local ok, s = pcall(textutils.serializeJSON, data)
        if ok and s then return s end
    end
    if textutils and textutils.serialize then
        local ok, s = pcall(textutils.serialize, data)
        if ok and s then return s end
    end
    return "{}"
end

local function decode(s)
    if not s or s == "" then return nil end
    if textutils and textutils.unserializeJSON then
        local ok, v = pcall(textutils.unserializeJSON, s)
        if ok and v ~= nil then return v end
    end
    if textutils and textutils.unserialize then
        local ok, v = pcall(textutils.unserialize, s)
        if ok and v ~= nil then return v end
    end
    return nil
end

-- ---------------------------------------------------------------
-- Пути и IO
-- ---------------------------------------------------------------

local function dirPath(userHome)
    local base = tostring(userHome or "")
    if base:sub(-1) == "/" then base = base:sub(1, -2) end
    return base .. "/.browser"
end

local function bookmarksPath(userHome) return dirPath(userHome) .. "/bookmarks.json" end
local function historyPath(userHome)   return dirPath(userHome) .. "/history.json"   end

local function fsOk()
    return type(fs) == "table"
end

local function readAll(path)
    if not fsOk() or not fs.exists or not fs.exists(path) then return nil end
    local ok, f = pcall(fs.open, path, "r")
    if not ok or not f then return nil end
    local content
    if f.readAll then
        content = f.readAll()
    else
        content = ""
        while true do
            local line = f.readLine and f.readLine()
            if not line then break end
            content = content .. line .. "\n"
        end
    end
    if f.close then f.close() end
    return content
end

local function writeAtomic(path, data)
    if not fsOk() then return false end
    local tmp = path .. ".tmp"
    if fs.exists and fs.exists(tmp) and fs.delete then
        pcall(fs.delete, tmp)
    end
    local ok, f = pcall(fs.open, tmp, "w")
    if not ok or not f then return false end
    if f.write then f.write(data) end
    if f.close then f.close() end
    -- Целевой файл должен отсутствовать для fs.move.
    if fs.exists and fs.exists(path) and fs.delete then
        pcall(fs.delete, path)
    end
    if fs.move then
        local okM = pcall(fs.move, tmp, path)
        if okM then return true end
    end
    -- Fallback: прямая запись.
    local ok2, f2 = pcall(fs.open, path, "w")
    if not ok2 or not f2 then return false end
    if f2.write then f2.write(data) end
    if f2.close then f2.close() end
    if fs.exists and fs.exists(tmp) and fs.delete then
        pcall(fs.delete, tmp)
    end
    return true
end

local function loadArray(path)
    local s = readAll(path)
    if not s then return {} end
    local v = decode(s)
    if type(v) ~= "table" then return {} end
    return v
end

local function saveArray(path, arr)
    return writeAtomic(path, encode(arr or {}))
end

-- ---------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------

function M.init(userHome)
    if not fsOk() then return false end
    local d = dirPath(userHome)
    if fs.exists and not fs.exists(d) then
        if fs.makeDir then
            pcall(fs.makeDir, d)
        end
    end
    return fs.exists and fs.exists(d) or false
end

-- ---- Закладки ----

function M.loadBookmarks(userHome)
    return loadArray(bookmarksPath(userHome))
end

function M.saveBookmarks(userHome, bookmarks)
    return saveArray(bookmarksPath(userHome), bookmarks)
end

function M.isBookmarked(userHome, url)
    if not url or url == "" then return false end
    local bm = M.loadBookmarks(userHome)
    for _, b in ipairs(bm) do
        if b.url == url then return true end
    end
    return false
end

function M.addBookmark(userHome, url, title)
    if not url or url == "" then return false end
    local bm = M.loadBookmarks(userHome)
    for _, b in ipairs(bm) do
        if b.url == url then return false end
    end
    table.insert(bm, {
        url = url,
        title = title or url,
        added_at = (os and os.epoch and os.epoch("utc")) or (os and os.time and os.time()) or 0,
    })
    M.saveBookmarks(userHome, bm)
    return true
end

function M.removeBookmark(userHome, url)
    if not url or url == "" then return false end
    local bm = M.loadBookmarks(userHome)
    local kept, removed = {}, false
    for _, b in ipairs(bm) do
        if b.url == url then
            removed = true
        else
            kept[#kept + 1] = b
        end
    end
    if removed then
        M.saveBookmarks(userHome, kept)
    end
    return removed
end

-- ---- История ----

function M.loadHistory(userHome)
    return loadArray(historyPath(userHome))
end

function M.saveHistory(userHome, history)
    return saveArray(historyPath(userHome), history)
end

function M.addHistory(userHome, url, title)
    if not url or url == "" then return false end
    local hist = M.loadHistory(userHome)
    local entry = {
        url = url,
        title = title or url,
        visited_at = (os and os.epoch and os.epoch("utc")) or (os and os.time and os.time()) or 0,
    }
    -- Если верхняя запись — тот же URL, просто обновим заголовок/время.
    if hist[1] and hist[1].url == url then
        hist[1] = entry
    else
        table.insert(hist, 1, entry)
    end
    -- Обрезаем до MAX_HISTORY.
    while #hist > MAX_HISTORY do
        table.remove(hist)
    end
    M.saveHistory(userHome, hist)
    return true
end

function M.clearHistory(userHome)
    return M.saveHistory(userHome, {})
end

M.MAX_HISTORY = MAX_HISTORY

return M
