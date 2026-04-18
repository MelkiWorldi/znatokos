-- Двухпанельный файловый менеджер. Tab — смена панели, Enter — войти/запустить,
-- F5 — копировать, F6 — переместить, F7 — mkdir, F8 — удалить, q — выход.
local theme  = znatokos.use("ui/theme")
local vfs    = znatokos.use("fs/vfs")
local dialog = znatokos.use("ui/dialog")

return function(user)
    local th = theme.get()
    local w, h = term.getSize()
    local panels = {
        { cwd = user and user.home or "/", sel = 1, scroll = 0 },
        { cwd = "/", sel = 1, scroll = 0 },
    }
    local active = 1

    local function listPanel(p)
        local entries = { ".." }
        local ok, list = pcall(vfs.list, p.cwd)
        if ok and type(list) == "table" then
            for _, n in ipairs(list) do entries[#entries + 1] = n end
            table.sort(entries, function(a, b)
                local ad = vfs.isDir(fs.combine(p.cwd, a))
                local bd = vfs.isDir(fs.combine(p.cwd, b))
                if ad ~= bd then return ad end
                return a < b
            end)
        end
        return entries
    end

    local function drawPanel(i)
        local p = panels[i]
        local x = (i - 1) * math.floor(w / 2) + 1
        local pw = math.floor(w / 2) - (i == 1 and 1 or 0)
        local ph = h - 2
        term.setBackgroundColor(i == active and th.selection_bg or th.menu_bg)
        term.setTextColor(i == active and th.selection_fg or th.menu_fg)
        term.setCursorPos(x, 1); term.write((" " .. p.cwd):sub(1, pw) .. string.rep(" ", pw - #p.cwd - 1))
        local entries = listPanel(p)
        for row = 1, ph do
            local idx = row + p.scroll
            local e = entries[idx]
            term.setCursorPos(x, row + 1)
            if e then
                local isDir = e == ".." or vfs.isDir(fs.combine(p.cwd, e))
                if idx == p.sel and i == active then
                    term.setBackgroundColor(th.selection_bg); term.setTextColor(th.selection_fg)
                else
                    term.setBackgroundColor(th.menu_bg)
                    term.setTextColor(isDir and colors.lightBlue or th.menu_fg)
                end
                local label = (isDir and "/" or " ") .. e
                term.write(label:sub(1, pw) .. string.rep(" ", math.max(0, pw - #label)))
            else
                term.setBackgroundColor(th.menu_bg); term.write(string.rep(" ", pw))
            end
        end
    end

    local function draw()
        term.setBackgroundColor(th.bg); term.clear()
        drawPanel(1); drawPanel(2)
        term.setBackgroundColor(th.taskbar_bg); term.setTextColor(th.taskbar_fg)
        term.setCursorPos(1, h); term.write(string.rep(" ", w))
        term.setCursorPos(1, h)
        term.write("Tab-панель Enter-войти F5-cp F6-mv F7-mkdir F8-del q-выход")
    end

    local function sel(p)
        local e = listPanel(p)[p.sel]
        if not e then return nil end
        return e, (e == ".." and fs.getDir(p.cwd) or fs.combine(p.cwd, e))
    end

    while true do
        draw()
        local ev = { os.pullEvent() }
        local p = panels[active]
        local entries = listPanel(p)
        if ev[1] == "key" then
            if ev[2] == keys.up and p.sel > 1 then p.sel = p.sel - 1
                if p.sel <= p.scroll then p.scroll = p.scroll - 1 end
            elseif ev[2] == keys.down and p.sel < #entries then p.sel = p.sel + 1
                if p.sel > p.scroll + (h - 2) then p.scroll = p.scroll + 1 end
            elseif ev[2] == keys.tab then active = 3 - active
            elseif ev[2] == keys.enter then
                local name, full = sel(p)
                if name and (name == ".." or vfs.isDir(full)) then
                    p.cwd = name == ".." and fs.getDir(p.cwd) or full
                    p.sel = 1; p.scroll = 0
                elseif name and full:find("%.lua$") then
                    term.setBackgroundColor(colors.black); term.clear()
                    term.setCursorPos(1, 1)
                    local fn = loadfile(full, nil, _G)
                    if fn then pcall(fn) end
                    print(""); print("[Enter чтобы продолжить]"); read()
                end
            elseif ev[2] == keys.f5 then
                local name, full = sel(p)
                if name and name ~= ".." then
                    local dst = fs.combine(panels[3 - active].cwd, name)
                    pcall(vfs.copy, full, dst)
                end
            elseif ev[2] == keys.f6 then
                local name, full = sel(p)
                if name and name ~= ".." then
                    local dst = fs.combine(panels[3 - active].cwd, name)
                    pcall(vfs.move, full, dst)
                end
            elseif ev[2] == keys.f7 then
                local n = dialog.input("Новый каталог", "Имя:")
                if n then pcall(vfs.makeDir, fs.combine(p.cwd, n)) end
            elseif ev[2] == keys.f8 then
                local name, full = sel(p)
                if name and name ~= ".." and dialog.confirm("Удалить?", name) then
                    pcall(vfs.delete, full)
                    if p.sel > 1 then p.sel = p.sel - 1 end
                end
            elseif ev[2] == keys.q then return
            end
        end
    end
end
