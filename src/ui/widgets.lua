-- UI-виджеты с поддержкой focus/blur/hover и dirty-flag.
-- Каждый widget — таблица с полями {x, y, w, h, focused, dirty, hovered},
-- методами draw(term), event(ev), и опционально onFocus/onBlur/onActivate.
local theme = znatokos.use("ui/theme")
local text  = znatokos.use("util/text")

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

function M.writeAt(t, x, y, s, fg, bg)
    t = t or term
    if fg then t.setTextColor(fg) end
    if bg then t.setBackgroundColor(bg) end
    t.setCursorPos(x, y); t.write(s)
end

function M.hit(w, mx, my)
    return mx >= w.x and mx <= w.x + w.w - 1
       and my >= w.y and my <= w.y + w.h - 1
end

-------------------------------------------------------
-- Button
-------------------------------------------------------
function M.button(opts)
    local b = {
        x = opts.x, y = opts.y,
        w = opts.w or (text.len(opts.label or "") + 4),
        h = opts.h or 1,
        label = opts.label or "OK",
        onClick = opts.onClick,
        focusable = true,
        focused = false,
        dirty = true,
    }
    function b:draw(t)
        local th = theme.get()
        t = t or term
        local bg = self.focused and th.btn_active_bg or th.btn_bg
        local fg = self.focused and th.btn_active_fg or th.btn_fg
        M.box(t, self.x, self.y, self.w, self.h, bg, fg)
        local centered = text.center(self.label, self.w)
        M.writeAt(t, self.x, self.y + math.floor(self.h / 2), centered, fg, bg)
        self.dirty = false
    end
    function b:onFocus() self.focused = true; self.dirty = true; self:draw() end
    function b:onBlur()  self.focused = false; self.dirty = true; self:draw() end
    function b:onActivate() if self.onClick then self.onClick() end end
    function b:event(ev)
        if ev[1] == "mouse_click" and ev[2] == 1 and M.hit(self, ev[3], ev[4]) then
            if self.onClick then self.onClick() end
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
    local l = {
        x = opts.x, y = opts.y,
        w = opts.w or text.len(opts.text or ""),
        h = 1,
        text = opts.text,
        fg = opts.fg, bg = opts.bg,
        align = opts.align or "left",
        focusable = false, dirty = true,
    }
    function l:draw(t)
        t = t or term
        local th = theme.get()
        local s = text.pad(self.text, self.w, self.align)
        M.writeAt(t, self.x, self.y, s,
            self.fg or th.fg, self.bg or th.bg)
        self.dirty = false
    end
    function l:event() return false end
    return l
end

-------------------------------------------------------
-- Input
-------------------------------------------------------
function M.input(opts)
    local i = {
        x = opts.x, y = opts.y,
        w = opts.w or 20, h = 1,
        value = opts.value or "",
        mask = opts.mask,
        focusable = true,
        focused = false,
        dirty = true,
        cursor = (opts.value and text.len(opts.value) or 0) + 1,
        onSubmit = opts.onSubmit,
    }
    function i:draw(t)
        local th = theme.get()
        t = t or term
        t.setBackgroundColor(self.focused and th.btn_active_bg or th.btn_bg)
        t.setTextColor(th.btn_fg)
        t.setCursorPos(self.x, self.y)
        local shown = self.mask and string.rep(self.mask, text.len(self.value)) or self.value
        if text.len(shown) > self.w then shown = text.sub(shown, -self.w) end
        t.write(text.pad(shown, self.w))
        if self.focused then
            t.setCursorPos(self.x + math.min(self.cursor - 1, self.w - 1), self.y)
            t.setCursorBlink(true)
        end
        self.dirty = false
    end
    function i:onFocus() self.focused = true; self.dirty = true; self:draw() end
    function i:onBlur()  self.focused = false; self.dirty = true; term.setCursorBlink(false); self:draw() end
    function i:onActivate() if self.onSubmit then self.onSubmit(self.value) end end
    function i:event(ev)
        if not self.focused then
            if ev[1] == "mouse_click" and ev[2] == 1 and M.hit(self, ev[3], ev[4]) then
                -- НЕ активируем self:onFocus напрямую — это путает focus-менеджер
                -- модального окна. Возвращаем специальный сигнал.
                return { requestFocus = self }
            end
            return false
        end
        if ev[1] == "char" then
            local chars = text.chars(self.value)
            table.insert(chars, self.cursor, ev[2])
            self.value = table.concat(chars)
            self.cursor = self.cursor + 1
            self:draw(); return true
        elseif ev[1] == "key" then
            if ev[2] == keys.backspace and self.cursor > 1 then
                local chars = text.chars(self.value)
                table.remove(chars, self.cursor - 1)
                self.value = table.concat(chars)
                self.cursor = self.cursor - 1
                self:draw(); return true
            elseif ev[2] == keys.delete then
                local chars = text.chars(self.value)
                if self.cursor <= #chars then
                    table.remove(chars, self.cursor)
                    self.value = table.concat(chars); self:draw()
                end
                return true
            elseif ev[2] == keys.left and self.cursor > 1 then
                self.cursor = self.cursor - 1; self:draw(); return true
            elseif ev[2] == keys.right and self.cursor <= text.len(self.value) then
                self.cursor = self.cursor + 1; self:draw(); return true
            elseif ev[2] == keys.home then self.cursor = 1; self:draw(); return true
            elseif ev[2] == keys["end"] then self.cursor = text.len(self.value) + 1; self:draw(); return true
            elseif ev[2] == keys.enter then
                if self.onSubmit then self.onSubmit(self.value) end
                return true
            end
        end
        return false
    end
    return i
end

-------------------------------------------------------
-- List
-------------------------------------------------------
function M.list(opts)
    local l = {
        x = opts.x, y = opts.y,
        w = opts.w or 20, h = opts.h or 5,
        items = opts.items or {},
        selected = opts.selected or 1,
        scroll = 0,
        focusable = true,
        focused = false,
        dirty = true,
        onSelect = opts.onSelect,
        onContext = opts.onContext,   -- ПКМ
    }
    function l:draw(t)
        local th = theme.get()
        t = t or term
        M.fill(t, self.x, self.y, self.w, self.h, th.menu_bg)
        for row = 1, self.h do
            local idx = row + self.scroll
            local it = self.items[idx]
            if it then
                local isSel = idx == self.selected and self.focused
                t.setBackgroundColor(isSel and th.selection_bg or th.menu_bg)
                t.setTextColor(isSel and th.selection_fg or th.menu_fg)
                t.setCursorPos(self.x, self.y + row - 1)
                t.write(text.pad(tostring(it), self.w))
            end
        end
        self.dirty = false
    end
    function l:onFocus() self.focused = true; self.dirty = true; self:draw() end
    function l:onBlur()  self.focused = false; self.dirty = true; self:draw() end
    function l:onActivate()
        if self.onSelect then self.onSelect(self.selected, self.items[self.selected]) end
    end
    function l:event(ev)
        if ev[1] == "mouse_click" and M.hit(self, ev[3], ev[4]) then
            local idx = ev[4] - self.y + 1 + self.scroll
            if self.items[idx] then
                self.selected = idx; self:draw()
                if ev[2] == 1 and self.onSelect then
                    self.onSelect(idx, self.items[idx])
                elseif ev[2] == 2 and self.onContext then
                    self.onContext(idx, self.items[idx], ev[3], ev[4])
                end
            end
            return true
        elseif ev[1] == "mouse_scroll" and M.hit(self, ev[3], ev[4]) then
            self.scroll = math.max(0,
                math.min(math.max(0, #self.items - self.h), self.scroll + ev[2]))
            self:draw(); return true
        elseif self.focused and ev[1] == "key" then
            if ev[2] == keys.up and self.selected > 1 then
                self.selected = self.selected - 1
                if self.selected <= self.scroll then self.scroll = self.scroll - 1 end
                self:draw(); return true
            elseif ev[2] == keys.down and self.selected < #self.items then
                self.selected = self.selected + 1
                if self.selected > self.scroll + self.h then self.scroll = self.scroll + 1 end
                self:draw(); return true
            end
        end
        return false
    end
    return l
end

-------------------------------------------------------
-- Menu (popup)
-------------------------------------------------------
function M.menu(opts)
    local items = opts.items or {}
    local labels = {}
    for i, it in ipairs(items) do labels[i] = it.label end
    local w = opts.w or 0
    for _, lb in ipairs(labels) do
        local l = text.len(lb)
        if l + 2 > w then w = l + 2 end
    end
    local m = {
        x = opts.x, y = opts.y, w = w, h = #items,
        items = items,
        focusable = true, focused = true,
        list = M.list({
            x = opts.x, y = opts.y, w = w, h = #items,
            items = labels, selected = 1,
            onSelect = function(idx)
                if items[idx] and items[idx].action then items[idx].action() end
                if opts.onClose then opts.onClose() end
            end,
        }),
    }
    m.list.focused = true
    function m:draw(t) self.list:draw(t) end
    function m:event(ev) return self.list:event(ev) end
    return m
end

return M
