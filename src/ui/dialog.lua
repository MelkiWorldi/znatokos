-- Модальные диалоги. Адаптивные размеры, word-wrap для длинных текстов,
-- Tab-навигация между кнопками.
local theme        = znatokos.use("ui/theme")
local widgets      = znatokos.use("ui/widgets")
local layout       = znatokos.use("ui/layout")
local focus        = znatokos.use("ui/focus")
local text         = znatokos.use("util/text")
local capabilities = znatokos.use("kernel/capabilities")

local M = {}

local function drawFrame(x, y, w, h, title)
    local th = theme.get()
    widgets.fill(term, x, y, w, h, th.bg)
    term.setBackgroundColor(th.title_bg); term.setTextColor(th.title_fg)
    term.setCursorPos(x, y)
    term.write(text.pad(" " .. (title or ""), w))
end

local function centerRect(w, h)
    local sw, sh = term.getSize()
    return math.floor((sw - w) / 2) + 1, math.floor((sh - h) / 2) + 1
end

local function runModal(widgetList, initialFocus)
    local current = initialFocus
    if current and current.onFocus then current:onFocus() end
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "key" then
            if ev[2] == keys.escape then return nil end
            local handled, nxt = focus.handleKey(widgetList, current, ev[2], false)
            if handled then
                -- focus уже применил onFocus/onBlur
                current = nxt
            end
        end
        if current and current.event then
            local r = current:event(ev)
            -- если виджет вернул {requestFocus = target}, переключаем фокус
            if type(r) == "table" and r.requestFocus then
                if current and current.onBlur then current:onBlur() end
                current = r.requestFocus
                if current.onFocus then current:onFocus() end
            end
        end
        -- дать шанс остальным виджетам обработать клик
        for _, w in ipairs(widgetList) do
            if w ~= current and w.event then
                local r = w:event(ev)
                if type(r) == "table" and r.requestFocus then
                    if current and current.onBlur then current:onBlur() end
                    current = r.requestFocus
                    if current.onFocus then current:onFocus() end
                end
            end
        end
        if _G._dialog_result ~= nil then
            local r = _G._dialog_result; _G._dialog_result = nil
            return r
        end
    end
end

-- message: одна кнопка OK
function M.message(title, body)
    local th = theme.get()
    local sw, sh = term.getSize()
    local maxW = math.max(30, math.min(sw - 4, 50))
    local lines = text.wrap(body or "", maxW - 4)
    local bodyW = 0
    for _, l in ipairs(lines) do bodyW = math.max(bodyW, text.len(l)) end
    local w = math.max(math.min(maxW, bodyW + 4), 20)
    local h = math.min(sh - 2, #lines + 4)
    local x, y = centerRect(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    for i, l in ipairs(lines) do
        if i + y > y + h - 3 then break end
        term.setCursorPos(x + 2, y + i)
        term.write(l)
    end

    local ok
    local btn = widgets.button({
        x = x + math.floor((w - 6) / 2), y = y + h - 2,
        w = 6, label = "OK",
        onClick = function() _G._dialog_result = true end,
    })
    btn:draw()
    runModal({ btn }, btn)
end

-- confirm: Yes/No
function M.confirm(title, body)
    local th = theme.get()
    local sw, sh = term.getSize()
    local maxW = math.max(30, math.min(sw - 4, 50))
    local lines = text.wrap(body or "", maxW - 4)
    local bodyW = 20
    for _, l in ipairs(lines) do bodyW = math.max(bodyW, text.len(l)) end
    local w = math.max(math.min(maxW, bodyW + 4), 20)
    local h = math.min(sh - 2, #lines + 4)
    local x, y = centerRect(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    for i, l in ipairs(lines) do
        term.setCursorPos(x + 2, y + i); term.write(l)
    end
    local yes = widgets.button({
        x = x + 2, y = y + h - 2, w = 8, label = "Да",
        onClick = function() _G._dialog_result = true end,
    })
    local no = widgets.button({
        x = x + w - 10, y = y + h - 2, w = 8, label = "Нет",
        onClick = function() _G._dialog_result = false end,
    })
    yes:draw(); no:draw()
    return runModal({ yes, no }, yes)
end

-- input: текстовое поле с OK/Cancel
function M.input(title, prompt, default, mask)
    local th = theme.get()
    local sw, sh = term.getSize()
    local w = math.min(sw - 4, 40); local h = 7
    local x, y = centerRect(w, h)
    drawFrame(x, y, w, h, title)
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
    term.setCursorPos(x + 2, y + 1); term.write(text.ellipsize(prompt or "", w - 4))
    local inp = widgets.input({
        x = x + 2, y = y + 3, w = w - 4, value = default or "", mask = mask,
        onSubmit = function(v) _G._dialog_result = v end,
    })
    local ok = widgets.button({
        x = x + 2, y = y + h - 2, w = 6, label = "OK",
        onClick = function() _G._dialog_result = inp.value end,
    })
    local ca = widgets.button({
        x = x + w - 8, y = y + h - 2, w = 8, label = "Отмена",
        onClick = function() _G._dialog_result = false end,
    })
    inp:draw(); ok:draw(); ca:draw()
    local r = runModal({ inp, ok, ca }, inp)
    if r == false then return nil end
    return r
end

-- permissionPrompt: модальное окно выдачи разрешений новому приложению.
-- Отрисовывает список capabilities с чекбоксами (dangerous по умолчанию off,
-- остальные on), кнопки [Разрешить всё] [Только отмеченные] [Отмена].
-- Возвращает таблицу {capId = bool} для всех capIds, либо nil при отмене.
function M.permissionPrompt(manifest, capIds)
    capIds = capIds or {}
    local th = theme.get()
    local sw, sh = term.getSize()
    local w = math.min(50, sw - 4)
    if w < 30 then w = math.min(30, sw) end
    local headerLines = 2            -- заголовок + пустая
    local footerLines = 4            -- пустая + "Всего..." + пустая + кнопки
    local h = headerLines + #capIds + footerLines
    if h > sh - 2 then h = sh - 2 end
    local x = math.floor((sw - w) / 2) + 1
    local y = math.floor((sh - h) / 2) + 1

    drawFrame(x, y, w, h, "Запрос разрешений")
    term.setBackgroundColor(th.bg); term.setTextColor(th.fg)

    -- Заголовок
    local appName = (manifest and manifest.name) or (manifest and manifest.id) or "?"
    local headerText = text.ellipsize(
        "Приложение \"" .. appName .. "\" запрашивает доступ:", w - 4)
    term.setCursorPos(x + 2, y + 1); term.write(headerText)

    -- Состояние чекбоксов: по умолчанию dangerous=off, остальные=on
    local state = {}
    for _, cid in ipairs(capIds) do
        local info = capabilities.describe(cid)
        state[cid] = not (info and info.dangerous)
    end

    -- Подсчёт выбранных (обновляется при переключении)
    local totalLine = {}   -- для ре-рендера
    local function countSelected()
        local n = 0
        for _, cid in ipairs(capIds) do if state[cid] then n = n + 1 end end
        return n
    end

    local function drawTotals()
        term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
        local s = ("Всего дать разрешений: %d из %d"):format(countSelected(), #capIds)
        term.setCursorPos(x + 2, y + headerLines + #capIds + 1)
        term.write(text.pad(s, w - 4))
    end

    -- Checkbox widget (inline — widgets.lua не предоставляет checkbox).
    local function makeCheckbox(cid, row)
        local info = capabilities.describe(cid) or
                     { id = cid, label = cid, description = "(неизвестная)", dangerous = false }
        local cb = {
            x = x + 2, y = y + headerLines + row - 1,
            w = w - 4, h = 1,
            capId = cid,
            info = info,
            focusable = true,
            focused = false,
            dirty = true,
        }
        function cb:draw(t)
            t = t or term
            local bg = th.bg
            local labelFg = self.info.dangerous and (th.error or colors.red) or th.fg
            t.setBackgroundColor(bg)
            -- чекбокс
            t.setCursorPos(self.x, self.y)
            t.setTextColor(self.focused and th.accent or th.fg)
            t.write(state[self.capId] and "[X] " or "[ ] ")
            -- id (фиксированная колонка ~14)
            local idW = 14
            local idStr = text.pad(text.ellipsize(self.info.id, idW), idW)
            t.setTextColor(labelFg)
            t.write(idStr)
            t.write(" ")
            -- описание + (опасно)
            local descSpace = self.w - 4 - idW - 1
            local desc = self.info.description or self.info.label or ""
            if self.info.dangerous then desc = desc .. "  (опасно)" end
            t.write(text.pad(text.ellipsize(desc, descSpace), descSpace))
            self.dirty = false
        end
        function cb:onFocus() self.focused = true; self:draw() end
        function cb:onBlur()  self.focused = false; self:draw() end
        function cb:toggle()
            state[self.capId] = not state[self.capId]
            self:draw()
            drawTotals()
        end
        function cb:onActivate() self:toggle() end
        function cb:event(ev)
            if ev[1] == "mouse_click" and ev[2] == 1 and widgets.hit(self, ev[3], ev[4]) then
                if not self.focused then
                    -- попросить focus-менеджер переключиться
                    self:toggle()
                    return { requestFocus = self }
                end
                self:toggle()
                return true
            end
            return false
        end
        return cb
    end

    local checkboxes = {}
    for i, cid in ipairs(capIds) do
        checkboxes[i] = makeCheckbox(cid, i)
        checkboxes[i]:draw()
    end
    drawTotals()

    -- Кнопки
    local btnY = y + h - 2
    local labelAll    = "Разрешить всё"
    local labelMarked = "Только отмеченные"
    local labelCancel = "Отмена"
    local wAll    = #labelAll + 2
    local wMarked = #labelMarked + 2
    local wCancel = #labelCancel + 2
    local totalBtn = wAll + wMarked + wCancel + 2
    if totalBtn > w - 2 then
        -- слишком узко — укорачиваем метки
        labelAll = "Всё"; labelMarked = "Отмеч."; labelCancel = "Отмена"
        wAll = #labelAll + 2; wMarked = #labelMarked + 2; wCancel = #labelCancel + 2
    end

    local result = nil    -- nil=cancel, table=answers
    local bAll = widgets.button({
        x = x + 2, y = btnY, w = wAll, label = labelAll,
        onClick = function()
            local r = {}
            for _, cid in ipairs(capIds) do r[cid] = true end
            result = r
            _G._dialog_result = "__done__"
        end,
    })
    local bMarked = widgets.button({
        x = x + 2 + wAll + 1, y = btnY, w = wMarked, label = labelMarked,
        onClick = function()
            local r = {}
            for _, cid in ipairs(capIds) do r[cid] = state[cid] and true or false end
            result = r
            _G._dialog_result = "__done__"
        end,
    })
    local bCancel = widgets.button({
        x = x + w - 2 - wCancel, y = btnY, w = wCancel, label = labelCancel,
        onClick = function()
            result = nil
            _G._dialog_result = "__cancel__"
        end,
    })
    bAll:draw(); bMarked:draw(); bCancel:draw()

    local widgetList = {}
    for _, cb in ipairs(checkboxes) do widgetList[#widgetList + 1] = cb end
    widgetList[#widgetList + 1] = bAll
    widgetList[#widgetList + 1] = bMarked
    widgetList[#widgetList + 1] = bCancel

    local initial = checkboxes[1] or bAll
    local r = runModal(widgetList, initial)
    if r == "__cancel__" or r == nil then return nil end
    return result
end

return M
