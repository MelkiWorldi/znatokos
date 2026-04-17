-- Простые UI-виджеты. Каждый виджет умеет draw и обрабатывать события.
local theme = znatokos.use("ui/theme")

local M = {}

-------------------------------------------------------
-- Утилиты отрисовки
-------------------------------------------------------
function M.fill(t, x, y, w, h, col)
    t = t or term
    t.setBackgroundColor(col)
    for i = 0, h - 1 do
        t.setCursorPos(x, y + i)
        t.write(string.rep(" ", w))
    end
end

function M.box(t, x, y, w, h, bg, fg)
    t = t or term
    M.fill(t, x, y, w, h, bg)
    if fg then t.setTextColor(fg) end
end

function M.writeAt(t, x, y, text, fg, bg)
    t = t or term
    if fg then t.setTextColor(fg) end
    if bg then t.setBackgroundColor(bg) end
    t.setCursorPos(x, y); t.write(text)
end

-------------------------------------------------------
-- Button
-------------------------------------------------------
function M.button(opts)
    local b = {
        x = opts.x, y = opts.y, w = opts.w or (#opts.label + 4), h = opts.h or 1,
        label = opts.label or "OK",
        onClick = opts.onClick,
        active = false,
    }
    function b:draw(t)
        local th = theme.get()
        local bg = self.active and th.btn_active_bg or th.btn_bg
        local fg = self.active and th.btn_active_fg or th.btn_fg
        M.box(t, self.x, self.y, self.w, self.h, bg, fg)
        local lx = self.x + math.floor((self.w - #self.label) / 2)
        M.writeAt(t, lx, self.y + math.floor(self.h / 2), self.label, fg, bg)
    end
    function b:hit(mx, my)
        return mx >= self.x and mx <= self.x + self.w - 1
           and my >= self.y and my <= self.y + self.h - 1
    end
    function b:event(ev)
        if ev[1] == "mouse_click" and self:hit(ev[3], ev[4]) then
            self.active = true; self:draw()
            if self.onClick then self.onClick() end
            sleep(0.05); self.active = false; self:draw()
            return true
        end
        return false
    end
    return b
end

-------------------------------------------------------
-- Label
-------------------------------------------------------
function M.label(opts)
    local l = { x = opts.x, y = opts.y, text = opts.text, fg = opts.fg, bg = opts.bg }
    function l:draw(t)
        M.writeAt(t, self.x, self.y, self.text, self.fg or theme.get().fg, self.bg or theme.get().bg)
    end
    return l
end

-------------------------------------------------------
-- Input: читаемое поле. event возвращает {done=true,value=...} при Enter.
-------------------------------------------------------
function M.input(opts)
    local i = {
        x = opts.x, y = opts.y, w = opts.w or 20,
        value = opts.value or "",
        mask  = opts.mask,
        focused = true,
        cursor = (opts.value and #opts.value or 0) + 1,
    }
    function i:draw(t)
        local th = theme.get()
        t = t or term
        t.setBackgroundColor(th.bg); t.setTextColor(th.fg)
        t.setCursorPos(self.x, self.y)
        local visible = self.mask and string.rep(self.mask, #self.value) or self.value
        if #visible > self.w then visible = visible:sub(-self.w) end
        t.write(visible .. string.rep("_", self.w - #visible))
        if self.focused then
            t.setCursorPos(self.x + math.min(self.cursor - 1, self.w - 1), self.y)
            t.setCursorBlink(true)
        end
    end
    function i:event(ev)
        if not self.focused then return false end
        if ev[1] == "char" then
            self.value = self.value:sub(1, self.cursor - 1) .. ev[2] .. self.value:sub(self.cursor)
            self.cursor = self.cursor + 1
            self:draw(); return true
        elseif ev[1] == "key" then
            if ev[2] == keys.backspace and self.cursor > 1 then
                self.value = self.value:sub(1, self.cursor - 2) .. self.value:sub(self.cursor)
                self.cursor = self.cursor - 1
                self:draw()
            elseif ev[2] == keys.delete then
                self.value = self.value:sub(1, self.cursor - 1) .. self.value:sub(self.cursor + 1)
                self:draw()
            elseif ev[2] == keys.left then
                if self.cursor > 1 then self.cursor = self.cursor - 1; self:draw() end
            elseif ev[2] == keys.right then
                if self.cursor <= #self.value then self.cursor = self.cursor + 1; self:draw() end
            elseif ev[2] == keys.enter then
                return { done = true, value = self.value }
            end
            return true
        end
        return false
    end
    return i
end

-------------------------------------------------------
-- List: вертикальный список с выделением, клавиши ↑↓, Enter.
-------------------------------------------------------
function M.list(opts)
    local l = {
        x = opts.x, y = opts.y, w = opts.w or 20, h = opts.h or 5,
        items = opts.items or {},
        selected = opts.selected or 1,
        scroll = 0,
        onSelect = opts.onSelect,
    }
    function l:draw(t)
        local th = theme.get()
        t = t or term
        M.fill(t, self.x, self.y, self.w, self.h, th.menu_bg)
        for i = 1, self.h do
            local idx = i + self.scroll
            local it = self.items[idx]
            if it then
                local isSel = idx == self.selected
                t.setBackgroundColor(isSel and th.selection_bg or th.menu_bg)
                t.setTextColor(isSel and th.selection_fg or th.menu_fg)
                t.setCursorPos(self.x, self.y + i - 1)
                local text = tostring(it)
                if #text > self.w then text = text:sub(1, self.w) end
                t.write(text .. string.rep(" ", self.w - #text))
            end
        end
    end
    function l:event(ev)
        if ev[1] == "key" then
            if ev[2] == keys.up and self.selected > 1 then
                self.selected = self.selected - 1
                if self.selected <= self.scroll then self.scroll = self.scroll - 1 end
                self:draw(); return true
            elseif ev[2] == keys.down and self.selected < #self.items then
                self.selected = self.selected + 1
                if self.selected > self.scroll + self.h then self.scroll = self.scroll + 1 end
                self:draw(); return true
            elseif ev[2] == keys.enter then
                if self.onSelect then self.onSelect(self.selected, self.items[self.selected]) end
                return true
            end
        elseif ev[1] == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if mx >= self.x and mx <= self.x + self.w - 1
               and my >= self.y and my <= self.y + self.h - 1 then
                local idx = my - self.y + 1 + self.scroll
                if self.items[idx] then
                    self.selected = idx; self:draw()
                    if self.onSelect then self.onSelect(idx, self.items[idx]) end
                end
                return true
            end
        elseif ev[1] == "mouse_scroll" then
            local mx, my = ev[3], ev[4]
            if mx >= self.x and mx <= self.x + self.w - 1
               and my >= self.y and my <= self.y + self.h - 1 then
                self.scroll = math.max(0, math.min(#self.items - self.h, self.scroll + ev[2]))
                self:draw(); return true
            end
        end
        return false
    end
    return l
end

-------------------------------------------------------
-- Menu: всплывающий список с действиями.
-------------------------------------------------------
function M.menu(opts)
    local items = opts.items or {}
    local labels = {}
    for i, it in ipairs(items) do labels[i] = it.label end
    local w = opts.w or 0
    for _, lb in ipairs(labels) do if #lb + 2 > w then w = #lb + 2 end end
    local m = {
        x = opts.x, y = opts.y, w = w, h = #items,
        items = items,
        list = M.list({
            x = opts.x, y = opts.y, w = w, h = #items,
            items = labels, selected = 1,
            onSelect = function(idx)
                if items[idx] and items[idx].action then items[idx].action() end
                if opts.onClose then opts.onClose() end
            end,
        }),
    }
    function m:draw(t) self.list:draw(t) end
    function m:event(ev) return self.list:event(ev) end
    return m
end

return M
