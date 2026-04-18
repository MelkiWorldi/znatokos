-- Магазин приложений ЗнатокOS.
-- Двухпанельный UI: слева — список приложений, справа — подробности и
-- кнопки действий. Три вкладки: Каталог / Установленные / Обновления.
-- Поиск по имени/id. Install/uninstall/update — синхронно, с индикацией
-- "Операция выполняется..." в preview-панели.

local theme        = znatokos.use("ui/theme")
local dialog       = znatokos.use("ui/dialog")
local text         = znatokos.use("util/text")
local store        = znatokos.use("pkg/store")
local manager      = znatokos.use("pkg/manager")
local capabilities = znatokos.use("kernel/capabilities")
local log          = znatokos.use("kernel/log")

return function(user)
    local th = theme.get()
    local userName = (user and user.user) or "?"

    ---------------------------------------------------------
    -- Состояние
    ---------------------------------------------------------
    local state = {
        tab         = "catalog",     -- catalog | installed | updates
        filter      = "",            -- текст поиска
        items       = {},            -- массив для текущей вкладки (сырой, без фильтра)
        view        = {},            -- отфильтрованный массив (отрисовывается)
        selectedIdx = 1,
        scrollY     = 0,
        searchFocus = false,         -- фокус на поисковой строке
        cacheNote   = "",            -- строка статуса (URL / ошибка)
        preview     = nil,           -- подробности выбранного элемента
        buttons     = {},            -- координаты кнопок действий {x,y,w,label,id}
    }

    ---------------------------------------------------------
    -- Нормализация элемента к универсальному виду
    -- {id, name, version, description, author, permissions, _status}
    -- _status: "available" | "installed" | "update"
    ---------------------------------------------------------
    local function normalizeItem(raw, fromTab)
        local it = { _raw = raw }
        if fromTab == "catalog" then
            it.id          = raw.id or "?"
            it.name        = raw.name or it.id
            it.version     = raw.version or "?"
            it.description = raw.description or ""
            it.author      = raw.author or ""
            it.permissions = raw.permissions or raw.caps or {}
        elseif fromTab == "installed" then
            local m = raw.manifest or {}
            it.id          = raw.id or m.id or "?"
            it.name        = m.name or it.id
            it.version     = raw.version or m.version or "?"
            it.description = m.description or ""
            it.author      = m.author or ""
            it.permissions = m.permissions or m.caps or {}
        elseif fromTab == "updates" then
            it.id          = raw.id or "?"
            it.name        = it.id
            it.version     = raw.storeVersion or "?"
            it.description = "Текущая: " .. tostring(raw.currentVersion)
                           .. " → в магазине: " .. tostring(raw.storeVersion)
            it.author      = ""
            it.permissions = {}
            it.currentVersion = raw.currentVersion
            it.storeVersion   = raw.storeVersion
        end
        -- Определяем статус
        if manager.isInstalled(it.id) then
            local inst = manager.getInstalled(it.id)
            it._installedVersion = inst and inst.version
            if fromTab == "updates" then
                it._status = "update"
            else
                it._status = "installed"
            end
        else
            it._status = "available"
        end
        return it
    end

    ---------------------------------------------------------
    -- Применение фильтра
    ---------------------------------------------------------
    local function applyFilter()
        local q = (state.filter or ""):lower()
        state.view = {}
        for _, it in ipairs(state.items) do
            if q == "" then
                state.view[#state.view + 1] = it
            else
                local hay = ((it.id or "") .. " " .. (it.name or "")):lower()
                if hay:find(q, 1, true) then
                    state.view[#state.view + 1] = it
                end
            end
        end
        if state.selectedIdx > #state.view then state.selectedIdx = #state.view end
        if state.selectedIdx < 1 then state.selectedIdx = 1 end
        if state.scrollY < 0 then state.scrollY = 0 end
    end

    ---------------------------------------------------------
    -- Загрузка вкладки
    ---------------------------------------------------------
    local function loadTab(tab)
        state.tab = tab
        state.items = {}
        state.view = {}
        state.selectedIdx = 1
        state.scrollY = 0

        if tab == "catalog" then
            local cfg = store.getConfig()
            state.cacheNote = cfg and cfg.url or ""
            local ok, apps_or_err, err = pcall(store.fetchIndex)
            -- fetchIndex возвращает (apps, err)
            local apps, fetchErr
            if ok then apps, fetchErr = apps_or_err, err
            else apps, fetchErr = nil, tostring(apps_or_err) end
            if apps then
                for _, raw in ipairs(apps) do
                    state.items[#state.items + 1] = normalizeItem(raw, "catalog")
                end
            else
                state.cacheNote = "offline: " .. tostring(fetchErr or "ошибка")
            end
        elseif tab == "installed" then
            state.cacheNote = "установлено на этом компьютере"
            local ok, list = pcall(manager.list)
            if ok and type(list) == "table" then
                for _, raw in ipairs(list) do
                    state.items[#state.items + 1] = normalizeItem(raw, "installed")
                end
            end
        elseif tab == "updates" then
            state.cacheNote = "проверка обновлений..."
            local ok, updates_or_err, err = pcall(manager.checkUpdates)
            local updates, chkErr
            if ok then updates, chkErr = updates_or_err, err
            else updates, chkErr = {}, tostring(updates_or_err) end
            if chkErr then state.cacheNote = "обновления: " .. tostring(chkErr)
            else state.cacheNote = ("доступно обновлений: %d"):format(#(updates or {})) end
            for _, raw in ipairs(updates or {}) do
                state.items[#state.items + 1] = normalizeItem(raw, "updates")
            end
        end
        applyFilter()
    end

    ---------------------------------------------------------
    -- Отрисовка
    ---------------------------------------------------------
    local W, H, LEFT_W, RIGHT_X, RIGHT_W

    local function computeLayout()
        W, H = term.getSize()
        LEFT_W  = math.max(20, math.floor(W * 0.55))
        RIGHT_X = LEFT_W + 2
        RIGHT_W = W - LEFT_W - 1
        if RIGHT_W < 10 then RIGHT_W = 10 end
    end

    local function writeAt(x, y, s, fg, bg)
        if fg then term.setTextColor(fg) end
        if bg then term.setBackgroundColor(bg) end
        term.setCursorPos(x, y); term.write(s)
    end

    local function drawHeader()
        term.setBackgroundColor(th.title_bg); term.setTextColor(th.title_fg)
        term.setCursorPos(1, 1); term.write(string.rep(" ", W))
        local left = " Магазин ЗнатокOS — " .. userName
        local right = state.cacheNote or ""
        writeAt(1, 1, text.ellipsize(left, W - 1), th.title_fg, th.title_bg)
        local rw = text.len(right)
        if rw > 0 and rw < W - text.len(left) - 3 then
            writeAt(W - rw, 1, right, th.title_fg, th.title_bg)
        end
    end

    local function drawTabs()
        term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
        term.setCursorPos(1, 2); term.write(string.rep(" ", W))
        local tabs = {
            { id = "catalog",   label = "Каталог" },
            { id = "installed", label = "Установленные" },
            { id = "updates",   label = "Обновления" },
        }
        local x = 2
        state._tabHits = {}
        for _, t in ipairs(tabs) do
            local lab = " " .. t.label .. " "
            local isActive = (state.tab == t.id)
            if isActive then
                term.setBackgroundColor(th.accent); term.setTextColor(th.title_fg)
            else
                term.setBackgroundColor(th.btn_bg); term.setTextColor(th.btn_fg)
            end
            term.setCursorPos(x, 2); term.write(lab)
            state._tabHits[#state._tabHits + 1] = { id = t.id, x1 = x, x2 = x + text.len(lab) - 1 }
            x = x + text.len(lab) + 1
        end
    end

    local function drawSearchBar()
        term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
        term.setCursorPos(1, 3); term.write(string.rep(" ", W))
        writeAt(2, 3, "Поиск: ", th.fg, th.bg)
        local boxX = 9
        local boxW = LEFT_W - 8
        if boxW < 10 then boxW = 10 end
        term.setBackgroundColor(state.searchFocus and th.btn_active_bg or th.btn_bg)
        term.setTextColor(state.searchFocus and th.btn_active_fg or th.btn_fg)
        term.setCursorPos(boxX, 3)
        local shown = state.filter or ""
        if text.len(shown) > boxW - 1 then shown = text.sub(shown, -(boxW - 1)) end
        term.write(text.pad(shown, boxW))
        state._searchHit = { x1 = boxX, x2 = boxX + boxW - 1, y = 3 }
        if state.searchFocus then
            term.setCursorPos(boxX + math.min(text.len(state.filter), boxW - 1), 3)
            term.setCursorBlink(true)
        else
            term.setCursorBlink(false)
        end
    end

    local function statusColor(status)
        if status == "installed" then return colors.lime
        elseif status == "update"  then return colors.orange
        else return colors.white end
    end

    local function statusLabel(status)
        if status == "installed" then return "Установлено"
        elseif status == "update"  then return "Обновление"
        else return "Доступно" end
    end

    local function drawList()
        local listY = 4
        local listH = H - listY
        term.setBackgroundColor(th.menu_bg); term.setTextColor(th.menu_fg)
        for r = 0, listH - 1 do
            term.setCursorPos(1, listY + r); term.write(string.rep(" ", LEFT_W))
        end
        if #state.view == 0 then
            local msg
            if state.tab == "updates" then msg = "Обновлений нет."
            elseif state.tab == "installed" then msg = "Нет установленных приложений."
            else msg = state.filter ~= "" and "Ничего не найдено." or "Каталог пуст или недоступен." end
            writeAt(2, listY + 1, text.ellipsize(msg, LEFT_W - 2), th.menu_fg, th.menu_bg)
            return
        end
        -- Авто-скролл
        if state.selectedIdx <= state.scrollY then state.scrollY = state.selectedIdx - 1 end
        if state.selectedIdx > state.scrollY + listH then state.scrollY = state.selectedIdx - listH end
        if state.scrollY < 0 then state.scrollY = 0 end

        for r = 1, listH do
            local idx = r + state.scrollY
            local it = state.view[idx]
            if it then
                local isSel = (idx == state.selectedIdx)
                local bg = isSel and th.selection_bg or th.menu_bg
                local fg = isSel and th.selection_fg or th.menu_fg
                term.setBackgroundColor(bg); term.setTextColor(fg)
                term.setCursorPos(1, listY + r - 1); term.write(string.rep(" ", LEFT_W))
                -- Статусная метка справа
                local sLabel = statusLabel(it._status)
                local sW = text.len(sLabel) + 2
                -- Имя + версия
                local verStr = " v" .. tostring(it.version)
                local nameArea = LEFT_W - sW - text.len(verStr) - 2
                if nameArea < 4 then nameArea = 4 end
                local nameStr = text.ellipsize(it.name or it.id or "?", nameArea)
                writeAt(2, listY + r - 1, nameStr, fg, bg)
                writeAt(2 + nameArea, listY + r - 1, verStr, fg, bg)
                -- Цвет статуса: если выбрано — не переопределяем текст, оставляем читаемым
                if isSel then
                    writeAt(LEFT_W - sW, listY + r - 1, sLabel, fg, bg)
                else
                    writeAt(LEFT_W - sW, listY + r - 1, sLabel, statusColor(it._status), bg)
                end
            end
        end
        -- Индикатор скролла
        if #state.view > listH then
            term.setBackgroundColor(th.menu_bg); term.setTextColor(th.accent)
            term.setCursorPos(LEFT_W, listY)
            term.write(state.scrollY > 0 and "^" or " ")
            term.setCursorPos(LEFT_W, listY + listH - 1)
            term.write(state.scrollY + listH < #state.view and "v" or " ")
        end
    end

    local function drawVSep()
        term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
        for y = 2, H do
            term.setCursorPos(LEFT_W + 1, y); term.write(" ")
        end
    end

    local function drawPreview()
        local it = state.view[state.selectedIdx]
        state.buttons = {}
        local px = RIGHT_X
        local py = 4
        local pw = RIGHT_W
        local ph = H - py
        term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
        for r = 0, ph - 1 do
            term.setCursorPos(px, py + r); term.write(string.rep(" ", pw))
        end
        if not it then
            writeAt(px, py, text.ellipsize("Выберите приложение слева.", pw), th.fg, th.bg)
            return
        end

        local y = py
        -- Имя
        writeAt(px, y, text.ellipsize(it.name or it.id or "?", pw), colors.white, th.bg)
        y = y + 1
        -- id
        writeAt(px, y, text.ellipsize("id: " .. (it.id or "?"), pw), colors.lightGray, th.bg)
        y = y + 1
        -- Версия
        writeAt(px, y, text.ellipsize("Версия: " .. tostring(it.version), pw), th.fg, th.bg)
        y = y + 1
        if it._installedVersion and it._installedVersion ~= it.version then
            writeAt(px, y, text.ellipsize("Установлено: " .. it._installedVersion, pw),
                colors.orange, th.bg)
            y = y + 1
        end
        if it.author and it.author ~= "" then
            writeAt(px, y, text.ellipsize("Автор: " .. it.author, pw), colors.lightGray, th.bg)
            y = y + 1
        end
        y = y + 1
        -- Описание
        if it.description and it.description ~= "" then
            for _, line in ipairs(text.wrap(it.description, pw)) do
                if y >= H - 3 then break end
                writeAt(px, y, line, th.fg, th.bg)
                y = y + 1
            end
            y = y + 1
        end
        -- Права
        if it.permissions and #it.permissions > 0 and y < H - 3 then
            writeAt(px, y, "Права:", th.accent, th.bg); y = y + 1
            for _, capId in ipairs(it.permissions) do
                if y >= H - 3 then break end
                local info = capabilities.describe(capId)
                local fg = (info and info.dangerous) and (th.error or colors.red) or th.fg
                local lbl = capId
                if info and info.dangerous then lbl = lbl .. " (опасно)" end
                writeAt(px, y, text.ellipsize(" - " .. lbl, pw), fg, th.bg)
                y = y + 1
            end
        end

        -- Кнопки действий — у подножия preview
        local by = H - 1
        local bx = px
        local function addButton(id, label)
            local w = text.len(label) + 2
            if bx + w > px + pw then return end
            term.setBackgroundColor(th.btn_bg); term.setTextColor(th.btn_fg)
            term.setCursorPos(bx, by); term.write(" " .. label .. " ")
            state.buttons[#state.buttons + 1] = {
                id = id, x1 = bx, x2 = bx + w - 1, y = by, label = label,
            }
            bx = bx + w + 1
        end

        if it._status == "available" then
            addButton("install", "Установить")
        elseif it._status == "installed" then
            addButton("uninstall", "Удалить")
        elseif it._status == "update" then
            addButton("update", "Обновить")
            addButton("uninstall", "Удалить")
        end
    end

    local function drawFooter()
        term.setBackgroundColor(th.taskbar_bg); term.setTextColor(th.taskbar_fg)
        term.setCursorPos(1, H); term.write(string.rep(" ", W))
        local hint = " ↑↓ выбор • Enter действие • Ctrl+F поиск • Tab вкладки • Esc выход "
        writeAt(1, H, text.ellipsize(hint, W), th.taskbar_fg, th.taskbar_bg)
    end

    local function drawAll()
        computeLayout()
        th = theme.get()
        term.setBackgroundColor(th.bg); term.clear()
        drawHeader()
        drawTabs()
        drawSearchBar()
        drawList()
        drawVSep()
        drawPreview()
        drawFooter()
        if state.searchFocus then
            term.setCursorPos(9 + math.min(text.len(state.filter), LEFT_W - 9), 3)
            term.setCursorBlink(true)
        else
            term.setCursorBlink(false)
        end
    end

    ---------------------------------------------------------
    -- Операции с блокирующей индикацией
    ---------------------------------------------------------
    local function showBusyMessage(title, msg)
        -- Затемнить правую панель и вывести сообщение
        computeLayout()
        local px = RIGHT_X; local py = 4; local pw = RIGHT_W; local ph = H - py
        term.setBackgroundColor(th.bg); term.setTextColor(th.fg)
        for r = 0, ph - 1 do
            term.setCursorPos(px, py + r); term.write(string.rep(" ", pw))
        end
        writeAt(px, py + 1, text.ellipsize(title, pw), th.accent, th.bg)
        local y = py + 3
        for _, line in ipairs(text.wrap(msg, pw)) do
            if y >= H - 2 then break end
            writeAt(px, y, line, th.fg, th.bg)
            y = y + 1
        end
    end

    local function doInstall(it)
        if not it then return end
        showBusyMessage("Установка", "Установка " .. (it.id or "?") .. "... подождите.")
        local ok, res, err = pcall(manager.install, it.id)
        if not ok then
            dialog.message("Ошибка установки", tostring(res))
        elseif res ~= true then
            dialog.message("Ошибка установки", tostring(err or res or "неизвестная ошибка"))
        else
            log.info("store-app: установлено " .. tostring(it.id))
        end
        loadTab(state.tab)
    end

    local function doUninstall(it)
        if not it then return end
        if not dialog.confirm("Удалить?", "Удалить приложение \"" .. (it.name or it.id) .. "\"?") then
            return
        end
        showBusyMessage("Удаление", "Удаление " .. (it.id or "?") .. "...")
        local ok, res, err = pcall(manager.uninstall, it.id)
        if not ok then
            dialog.message("Ошибка", tostring(res))
        elseif res ~= true then
            dialog.message("Ошибка", tostring(err or res or "неизвестная ошибка"))
        end
        loadTab(state.tab)
    end

    local function doUpdate(it)
        if not it then return end
        showBusyMessage("Обновление", "Обновление " .. (it.id or "?") .. "... подождите.")
        local ok, res, err = pcall(manager.update, it.id)
        if not ok then
            dialog.message("Ошибка обновления", tostring(res))
        elseif res ~= true then
            dialog.message("Ошибка обновления", tostring(err or res or "неизвестная ошибка"))
        end
        loadTab(state.tab)
    end

    local function runAction(actionId)
        local it = state.view[state.selectedIdx]
        if not it then return end
        if actionId == "install"   then doInstall(it)
        elseif actionId == "uninstall" then doUninstall(it)
        elseif actionId == "update"    then doUpdate(it) end
    end

    local function primaryActionFor(it)
        if not it then return nil end
        if it._status == "available" then return "install"
        elseif it._status == "update" then return "update"
        else return nil end
    end

    ---------------------------------------------------------
    -- Переключение вкладок
    ---------------------------------------------------------
    local TABS_ORDER = { "catalog", "installed", "updates" }
    local function tabIndex(id)
        for i, t in ipairs(TABS_ORDER) do if t == id then return i end end
        return 1
    end
    local function nextTab()
        local i = tabIndex(state.tab) % #TABS_ORDER + 1
        loadTab(TABS_ORDER[i])
    end
    local function prevTab()
        local i = tabIndex(state.tab) - 1
        if i < 1 then i = #TABS_ORDER end
        loadTab(TABS_ORDER[i])
    end

    ---------------------------------------------------------
    -- Инициализация
    ---------------------------------------------------------
    computeLayout()
    term.setBackgroundColor(th.bg); term.clear()
    drawHeader(); drawTabs(); drawSearchBar(); drawFooter()
    showBusyMessage("Загрузка", "Загрузка каталога...")
    local okInit, initErr = pcall(loadTab, "catalog")
    if not okInit then
        log.error("store-app: loadTab catalog: " .. tostring(initErr))
        state.tab = "installed"
        pcall(loadTab, "installed")
    end
    drawAll()

    ---------------------------------------------------------
    -- Главный цикл событий
    ---------------------------------------------------------
    while true do
        local ev = { os.pullEvent() }
        local et = ev[1]

        if et == "term_resize" or et == "znatokos:resize" then
            drawAll()

        elseif et == "mouse_click" then
            local btn, mx, my = ev[2], ev[3], ev[4]

            -- вкладки (строка 2)
            if my == 2 and state._tabHits then
                for _, hit in ipairs(state._tabHits) do
                    if mx >= hit.x1 and mx <= hit.x2 then
                        if state.tab ~= hit.id then loadTab(hit.id) end
                        state.searchFocus = false
                        drawAll()
                        goto continue
                    end
                end
            end

            -- поиск (строка 3)
            if my == 3 and state._searchHit
               and mx >= state._searchHit.x1 and mx <= state._searchHit.x2 then
                state.searchFocus = true
                drawAll()
                goto continue
            end

            -- кнопки preview
            for _, b in ipairs(state.buttons or {}) do
                if my == b.y and mx >= b.x1 and mx <= b.x2 then
                    state.searchFocus = false
                    runAction(b.id)
                    drawAll()
                    goto continue
                end
            end

            -- список (левая панель, строки 4..H-1)
            if mx >= 1 and mx <= LEFT_W and my >= 4 and my <= H - 1 then
                local idx = (my - 4) + 1 + state.scrollY
                if state.view[idx] then
                    state.selectedIdx = idx
                    state.searchFocus = false
                    drawAll()
                end
                goto continue
            end

            -- клик по preview-области — снять фокус с поиска
            state.searchFocus = false
            drawAll()

        elseif et == "mouse_scroll" then
            local dir, mx, my = ev[2], ev[3], ev[4]
            if mx <= LEFT_W and my >= 4 then
                local listH = H - 4
                state.scrollY = math.max(0,
                    math.min(math.max(0, #state.view - listH), state.scrollY + dir))
                drawAll()
            end

        elseif et == "char" then
            if state.searchFocus then
                state.filter = state.filter .. ev[2]
                applyFilter()
                drawAll()
            end

        elseif et == "key" then
            local k = ev[2]
            if k == keys.escape then
                if state.searchFocus then
                    state.searchFocus = false
                    drawAll()
                else
                    term.setCursorBlink(false)
                    return
                end
            elseif k == keys.tab then
                nextTab(); state.searchFocus = false; drawAll()
            elseif state.searchFocus then
                -- Ввод в поисковой строке
                if k == keys.backspace then
                    if state.filter ~= "" then
                        state.filter = text.sub(state.filter, 1, text.len(state.filter) - 1)
                        applyFilter(); drawAll()
                    end
                elseif k == keys.enter then
                    state.searchFocus = false; applyFilter(); drawAll()
                end
            else
                if k == keys.up then
                    if state.selectedIdx > 1 then state.selectedIdx = state.selectedIdx - 1 end
                    drawAll()
                elseif k == keys.down then
                    if state.selectedIdx < #state.view then state.selectedIdx = state.selectedIdx + 1 end
                    drawAll()
                elseif k == keys.pageUp then
                    state.selectedIdx = math.max(1, state.selectedIdx - (H - 5))
                    drawAll()
                elseif k == keys.pageDown then
                    state.selectedIdx = math.min(#state.view, state.selectedIdx + (H - 5))
                    drawAll()
                elseif k == keys.home then
                    state.selectedIdx = 1; state.scrollY = 0; drawAll()
                elseif k == keys["end"] then
                    state.selectedIdx = #state.view; drawAll()
                elseif k == keys.enter then
                    local it = state.view[state.selectedIdx]
                    local act = primaryActionFor(it)
                    if act then runAction(act); drawAll() end
                elseif k == keys.f then
                    -- Ctrl+F обрабатываем через проверку зажатого Ctrl:
                    -- в CC:Tweaked нет встроенного getKeyState без side-effect,
                    -- но мы можем использовать keys.leftCtrl как флаг через
                    -- отдельный путь — здесь просто реагируем на 'f' вне поиска:
                    -- это не идеально, но удобно. Пользователи любых раскладок
                    -- смогут также кликнуть по полю поиска.
                    state.searchFocus = true; drawAll()
                elseif k == keys.slash then
                    -- Альтернатива: '/' тоже открывает поиск
                    state.searchFocus = true; drawAll()
                elseif k == keys.f5 then
                    loadTab(state.tab); drawAll()
                end
            end
        end

        ::continue::
    end
end
