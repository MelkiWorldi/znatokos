-- Менеджер окон поверх встроенного API window.create.
-- Каждое окно — таблица {id, title, win, x, y, w, h, visible, owner}.
local theme = znatokos.use("ui/theme")

local M = {}
local windows = {}
local nextId = 1
local focused = nil
local parentTerm = term.current()

function M.setParent(t) parentTerm = t end
function M.getParent() return parentTerm end

function M.create(opts)
    opts = opts or {}
    local pw, ph = parentTerm.getSize()
    local w = opts.w or (pw - 4)
    local h = opts.h or (ph - 3)
    local x = opts.x or 2
    local y = opts.y or 2
    if x + w - 1 > pw then w = pw - x end
    if y + h - 1 > ph - 1 then h = ph - 1 - y end

    local win = window.create(parentTerm, x, y, w, h, false)
    win.setBackgroundColor(theme.get().bg)
    win.setTextColor(theme.get().fg)
    win.clear()
    local entry = {
        id = nextId,
        title = opts.title or "Окно",
        win = win,
        x = x, y = y, w = w, h = h,
        visible = false,
        owner = opts.owner or 0,
    }
    nextId = nextId + 1
    windows[entry.id] = entry
    return entry
end

function M.list()
    local arr = {}
    for _, w in pairs(windows) do arr[#arr + 1] = w end
    table.sort(arr, function(a, b) return a.id < b.id end)
    return arr
end

function M.destroy(id)
    local w = windows[id]; if not w then return end
    w.win.setVisible(false)
    windows[id] = nil
    if focused == id then
        focused = nil
        local list = M.list()
        if #list > 0 then M.focus(list[#list].id) end
    end
    M.redrawAll()
end

function M.focus(id)
    local w = windows[id]; if not w then return end
    focused = id
    -- Делаем фокусное окно последним в отрисовке
    for _, ow in pairs(windows) do ow.win.setVisible(false) end
    for _, ow in pairs(windows) do
        if ow.id ~= id and ow.visible then ow.win.redraw() end
    end
    w.visible = true
    w.win.setVisible(true)
    w.win.redraw()
end

function M.getFocused()
    return focused and windows[focused] or nil
end

function M.nextWindow()
    local list = M.list()
    if #list == 0 then return end
    local idx = 1
    for i, w in ipairs(list) do if w.id == focused then idx = i break end end
    idx = (idx % #list) + 1
    M.focus(list[idx].id)
end

function M.redrawAll()
    parentTerm.setBackgroundColor(theme.get().desktop or colors.cyan)
    parentTerm.clear()
    for _, w in pairs(windows) do
        if w.visible then w.win.redraw() end
    end
end

function M.drawTitleBar(w)
    local t = theme.get()
    local win = w.win
    local prev = term.redirect(win)
    win.setCursorPos(1, 1)
    win.setBackgroundColor(focused == w.id and t.title_bg or t.title_bg_inactive)
    win.setTextColor(t.title_fg)
    local label = " " .. w.title .. string.rep(" ", w.w - #w.title - 3) .. "X "
    win.write(label:sub(1, w.w))
    term.redirect(prev)
end

function M.getById(id) return windows[id] end

return M
