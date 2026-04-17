-- Приложение настроек. Тема, метка, сетевой репо.
local theme   = znatokos.use("ui/theme")
local widgets = znatokos.use("ui/widgets")
local dialog  = znatokos.use("ui/dialog")
local repo    = znatokos.use("pkg/repo")
local net     = znatokos.use("net/rednet")

return function()
    local th = theme.get()
    while true do
        term.setBackgroundColor(th.bg); term.clear()
        term.setCursorPos(2, 1); term.setTextColor(th.accent); term.write("== Настройки ==")
        term.setTextColor(th.fg)
        term.setCursorPos(2, 3); term.write("Тема:       " .. theme.name())
        term.setCursorPos(2, 4); term.write("Метка:      " .. net.label())
        term.setCursorPos(2, 5); term.write("Репо pkg:   " .. (repo.getUrl() or "(встроенный)"))
        term.setCursorPos(2, 7); term.write("Выберите действие:")
        local list = widgets.list({
            x = 2, y = 9, w = 30, h = 6,
            items = { "Сменить тему", "Сменить метку", "Настроить URL репо", "Выход" },
            selected = 1,
        })
        list:draw(term)
        local done = false
        while not done do
            local ev = { os.pullEvent() }
            if ev[1] == "key" and ev[2] == keys.enter then
                local i = list.selected
                if i == 1 then
                    local names = theme.listNames()
                    local m = widgets.list({ x = 2, y = 16, w = 20, h = #names, items = names })
                    m:draw(term)
                    while true do
                        local e = { os.pullEvent() }
                        m:event(e)
                        if e[1] == "key" and e[2] == keys.enter then
                            theme.set(names[m.selected]); break
                        elseif e[1] == "key" and e[2] == keys.escape then break end
                    end
                    th = theme.get()
                    done = true
                elseif i == 2 then
                    local v = dialog.input("Метка", "Имя компьютера:", net.label())
                    if v then os.setComputerLabel(v) end
                    done = true
                elseif i == 3 then
                    local v = dialog.input("Репо", "URL JSON-каталога:", repo.getUrl() or "")
                    if v and v ~= "" then repo.setUrl(v) end
                    done = true
                elseif i == 4 then return end
            elseif ev[1] == "key" and ev[2] == keys.escape then return
            else list:event(ev) end
        end
    end
end
