-- Приложение настроек: тема, метка, репо, видимый курсор.
local theme   = znatokos.use("ui/theme")
local widgets = znatokos.use("ui/widgets")
local dialog  = znatokos.use("ui/dialog")
local repo    = znatokos.use("pkg/repo")
local net     = znatokos.use("net/rednet")
local pointer = znatokos.use("ui/pointer")
local text    = znatokos.use("util/text")

return function()
    while true do
        local th = theme.get()
        local sw, sh = term.getSize()
        term.setBackgroundColor(th.bg); term.clear()
        term.setCursorPos(2, 1); term.setTextColor(th.accent)
        term.write("Настройки")
        term.setTextColor(th.fg)

        local info = {
            ("Тема:        %s"):format(theme.name()),
            ("Метка:       %s"):format(net.label()),
            ("Репо pkg:    %s"):format(repo.getUrl() or "(встроенный)"),
            ("Курсор:      %s"):format(pointer.isEnabled() and "включён" or "выключен"),
        }
        for i, l in ipairs(info) do
            term.setCursorPos(2, 2 + i); term.write(text.ellipsize(l, sw - 4))
        end

        local itemsList = {
            "Сменить тему",
            "Сменить метку",
            "Настроить URL репо",
            "Включить/выключить видимый курсор",
            "Выход",
        }
        local list = widgets.list({
            x = 2, y = 8, w = math.min(40, sw - 4), h = math.min(#itemsList, sh - 10),
            items = itemsList, selected = 1,
        })
        list:onFocus()
        list:draw(term)

        while true do
            local ev = { os.pullEvent() }
            if ev[1] == "key" and ev[2] == keys.enter then
                local i = list.selected
                if i == 1 then
                    local names = theme.listNames()
                    local preview = {}
                    for _, n in ipairs(names) do preview[#preview + 1] = n end
                    local m = widgets.list({
                        x = 2, y = 14, w = 20, h = math.min(#names, sh - 15),
                        items = preview, selected = 1,
                    })
                    m:onFocus(); m:draw(term)
                    while true do
                        local e = { os.pullEvent() }
                        m:event(e)
                        if e[1] == "key" and e[2] == keys.enter then
                            theme.set(names[m.selected]); break
                        elseif e[1] == "key" and e[2] == keys.escape then break end
                    end
                    break
                elseif i == 2 then
                    local v = dialog.input("Метка", "Имя компьютера:", net.label())
                    if v then os.setComputerLabel(v) end
                    break
                elseif i == 3 then
                    local v = dialog.input("Репо", "URL JSON-каталога:", repo.getUrl() or "")
                    if v and v ~= "" then repo.setUrl(v) end
                    break
                elseif i == 4 then
                    pointer.setEnabled(not pointer.isEnabled())
                    break
                elseif i == 5 then return end
            elseif ev[1] == "key" and ev[2] == keys.escape then
                return
            elseif ev[1] == "znatokos:resize" or ev[1] == "term_resize" then
                break  -- перерисовать в след. итерации
            else
                list:event(ev)
            end
        end
    end
end
