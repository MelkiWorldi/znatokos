-- Менеджер окон с chrome: рамка + title bar + кнопка закрытия.
-- Каждое окно = 2 CC-window'a: "chrome" (внешний) и "content" (внутренний).
-- Поддерживает перетаскивание за title bar, фокус, z-order.
local theme = znatokos.use("ui/theme")
local text  = znatokos.use("util/text")

local M = {}
local windows = {}   -- id → entry
local zorder = {}    -- список id в порядке отрисовки: нижние → верхние
local nextId = 1
local focused = nil
local parentTerm = term.current()
local onClose = nil  -- колбэк close(id)

function M.setParent(t)
    parentTerm = t
    -- пересоздать chrome/content для существующих окон было бы идеально,
    -- но при смене display это делается через reflow()
end
function M.getParent() return parentTerm end

function M.setOnClose(fn) onClose = fn end

local function zPromote(id)
    for i, v in ipairs(zorder) do
        if v == id then table.remove(zorder, i); break end
    end
    zorder[#zorder + 1] = id
end

local function zRemove(id)
    for i, v in ipairs(zorder) do
        if v == id then table.remove(zorder, i); break end
    end
end

--------------------------------------------------------------
-- создание окна
--------------------------------------------------------------
function M.create(opts)
    opts = opts or {}
    local pw, ph = parentTerm.getSize()
    -- допустимая область — всё кроме taskbar (1 строка снизу)
    local maxW, maxH = pw, ph - 1
    local w = opts.w or math.min(45, maxW - 4)
    local h = opts.h or math.min(15, maxH - 2)
    if w > maxW then w = maxW end
    if h > maxH then h = maxH end
    local x = opts.x or math.max(1, math.floor((pw - w) / 2) + 1)
    local y = opts.y or math.max(1, math.floor((ph - 1 - h) / 2) + 1)
    if x + w - 1 > pw then x = pw - w + 1 end
    if y + h > ph then y = ph - h end
    if x < 1 then x = 1 end
    if y < 1 then y = 1 end

    local hasChrome = opts.chrome ~= false
    local chromeWin, contentWin
    if hasChrome then
        chromeWin = window.create(parentTerm, x, y, w, h, false)
        contentWin = window.create(chromeWin, 2, 2, w - 2, h - 2, true)
    else
        contentWin = window.create(parentTerm, x, y, w, h, false)
    end

    contentWin.setBackgroundColor(theme.get().bg)
    contentWin.setTextColor(theme.get().fg)
    contentWin.clear()

    local entry = {
        id = nextId,
        title = opts.title or "Окно",
        icon = opts.icon,
        chrome = chromeWin,
        win = contentWin,
        hasChrome = hasChrome,
        x = x, y = y, w = w, h = h,
        visible = false,
        owner = opts.owner or 0,
        closable = opts.closable ~= false,
        draggable = opts.draggable ~= false and hasChrome,
        resizable = opts.resizable or false,
    }
    nextId = nextId + 1
    windows[entry.id] = entry
    zorder[#zorder + 1] = entry.id
    return entry
end

function M.list()
    local arr = {}
    for _, id in ipairs(zorder) do
        if windows[id] then arr[#arr + 1] = windows[id] end
    end
    return arr
end

function M.getById(id) return windows[id] end
function M.getFocused() return focused and windows[focused] or nil end

--------------------------------------------------------------
-- отрисовка chrome (рамка + title bar + кнопка X)
--------------------------------------------------------------
local function drawChrome(w)
    if not w.hasChrome then return end
    local t = theme.get()
    local ch = w.chrome
    local isFocus = focused == w.id

    local prev = term.redirect(ch)
    -- верхняя строка = title bar
    ch.setCursorPos(1, 1)
    ch.setBackgroundColor(isFocus and t.title_bg or t.title_bg_inactive)
    ch.setTextColor(t.title_fg)
    local titleSpace = w.w - (w.closable and 3 or 0)
    local title = text.ellipsize(" " .. (w.title or ""), titleSpace)
    ch.write(text.pad(title, titleSpace))
    if w.closable then
        ch.setBackgroundColor(t.error or colors.red)
        ch.setTextColor(t.title_fg)
        ch.write("[X]")
        w._closeX = w.w - 2  -- локальные координаты в chrome
    end

    -- боковые рамки (+ низ)
    ch.setBackgroundColor(t.bg); ch.setTextColor(t.fg)
    for row = 2, w.h do
        ch.setCursorPos(1, row); ch.write("|")
        ch.setCursorPos(w.w, row); ch.write("|")
    end
    ch.setCursorPos(1, w.h)
    ch.write("+" .. string.rep("-", w.w - 2) .. "+")

    term.redirect(prev)
end

function M.redrawAll()
    parentTerm.setBackgroundColor(theme.get().desktop or colors.cyan)
    parentTerm.clear()
    os.queueEvent("znatokos:redraw")
    for _, id in ipairs(zorder) do
        local w = windows[id]
        if w and w.visible then
            drawChrome(w)
            w.chrome = w.chrome or w.win
            w.chrome.redraw()
        end
    end
end

function M.focus(id)
    local w = windows[id]; if not w then return end
    focused = id
    zPromote(id)
    for _, ow in pairs(windows) do
        if ow.chrome then ow.chrome.setVisible(false) else ow.win.setVisible(false) end
    end
    -- Перерисовываем в z-order
    for _, oid in ipairs(zorder) do
        local ow = windows[oid]
        if ow and ow.visible then
            if ow.chrome then ow.chrome.setVisible(true); drawChrome(ow); ow.chrome.redraw()
            else ow.win.setVisible(true); ow.win.redraw() end
        end
    end
    w.visible = true
    local mainW = w.chrome or w.win
    mainW.setVisible(true)
    drawChrome(w)
    mainW.redraw()
end

function M.destroy(id)
    local w = windows[id]; if not w then return end
    if w.chrome then w.chrome.setVisible(false) else w.win.setVisible(false) end
    windows[id] = nil
    zRemove(id)
    if focused == id then
        focused = nil
        local list = M.list()
        if #list > 0 then M.focus(list[#list].id) end
    end
    M.redrawAll()
end

function M.nextWindow()
    local list = M.list()
    if #list == 0 then return end
    local idx = 1
    for i, w in ipairs(list) do if w.id == focused then idx = i break end end
    idx = (idx % #list) + 1
    M.focus(list[idx].id)
end

--------------------------------------------------------------
-- hit-test: координата в мире → что попало (title_x, title_drag, close, content)
--------------------------------------------------------------
function M.hitTest(gx, gy)
    -- Ищем самое верхнее окно, в которое попали. z-order: высокие в конце.
    for i = #zorder, 1, -1 do
        local w = windows[zorder[i]]
        if w and w.visible
           and gx >= w.x and gx <= w.x + w.w - 1
           and gy >= w.y and gy <= w.y + w.h - 1 then
            local lx = gx - w.x + 1
            local ly = gy - w.y + 1
            local hitType = "content"
            if w.hasChrome then
                if ly == 1 then
                    if w.closable and lx >= w.w - 2 then
                        hitType = "close"
                    else
                        hitType = "title"
                    end
                elseif ly == w.h or lx == 1 or lx == w.w then
                    hitType = "frame"
                end
            end
            return w, hitType, lx, ly
        end
    end
    return nil
end

--------------------------------------------------------------
-- drag: удерживаем состояние между mouse_click и mouse_drag / up
--------------------------------------------------------------
local drag = nil

function M.beginDrag(id, gx, gy)
    local w = windows[id]; if not w or not w.draggable then return end
    drag = { id = id, ox = gx - w.x, oy = gy - w.y }
end

function M.updateDrag(gx, gy)
    if not drag then return end
    local w = windows[drag.id]; if not w then drag = nil; return end
    local pw, ph = parentTerm.getSize()
    local nx = math.max(1, math.min(pw - w.w + 1, gx - drag.ox))
    local ny = math.max(1, math.min(ph - 1 - w.h + 1, gy - drag.oy))
    if nx ~= w.x or ny ~= w.y then
        w.x = nx; w.y = ny
        if w.chrome then
            w.chrome.reposition(nx, ny)
            -- content живёт внутри chrome (относительная позиция 2,2) —
            -- при reposition chrome его позиция в parent terminal обновляется автоматически
        else
            w.win.reposition(nx, ny)
        end
        M.redrawAll()
    end
end

function M.endDrag() drag = nil end
function M.isDragging() return drag ~= nil end

--------------------------------------------------------------
-- reflow после ресайза родительского терминала
--------------------------------------------------------------
function M.reflow()
    local pw, ph = parentTerm.getSize()
    for _, w in pairs(windows) do
        local newX, newY = w.x, w.y
        local newW, newH = w.w, w.h
        if newW > pw then newW = pw end
        if newH > ph - 1 then newH = ph - 1 end
        if newX + newW - 1 > pw then newX = math.max(1, pw - newW + 1) end
        if newY + newH - 1 > ph - 1 then newY = math.max(1, ph - 1 - newH + 1) end
        if newX ~= w.x or newY ~= w.y or newW ~= w.w or newH ~= w.h then
            w.x, w.y, w.w, w.h = newX, newY, newW, newH
            if w.chrome then
                w.chrome.reposition(newX, newY, newW, newH)
                w.win.reposition(2, 2, newW - 2, newH - 2)
            else
                w.win.reposition(newX, newY, newW, newH)
            end
        end
    end
    M.redrawAll()
end

--------------------------------------------------------------
-- close by click on [X]
--------------------------------------------------------------
function M.requestClose(id)
    if onClose then onClose(id) end
    -- Убить задачу, которая владеет этим окном. Сам destroy произойдёт
    -- в scheduler'е при обработке terminate_pid — не дублируем здесь.
    local ok, sched = pcall(znatokos.use, "kernel/scheduler")
    if ok and sched.killByWindow and sched.killByWindow(id) then
        return  -- scheduler сам удалит окно
    end
    -- Нет задачи (окно без владельца) — удалить напрямую
    M.destroy(id)
end

return M
