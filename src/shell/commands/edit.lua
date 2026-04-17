-- edit <файл> — простой редактор с подсветкой Lua.
local vfs   = znatokos.use("fs/vfs")
local theme = znatokos.use("ui/theme")

local KEYWORDS = {
    ["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,
    ["false"]=1,["for"]=1,["function"]=1,["goto"]=1,["if"]=1,["in"]=1,
    ["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,["return"]=1,
    ["then"]=1,["true"]=1,["until"]=1,["while"]=1,
}

local function highlight(line)
    local out = {}
    local i, n = 1, #line
    while i <= n do
        local c = line:sub(i, i)
        if c == "-" and line:sub(i + 1, i + 1) == "-" then
            out[#out + 1] = { text = line:sub(i), col = colors.gray }
            break
        elseif c == '"' or c == "'" then
            local q = c; local j = i + 1
            while j <= n and line:sub(j, j) ~= q do
                if line:sub(j, j) == "\\" then j = j + 1 end
                j = j + 1
            end
            out[#out + 1] = { text = line:sub(i, j), col = colors.lime }
            i = j + 1
        elseif c:match("[%a_]") then
            local j = i
            while j <= n and line:sub(j, j):match("[%w_]") do j = j + 1 end
            local word = line:sub(i, j - 1)
            local col = colors.white
            if KEYWORDS[word] then col = colors.orange end
            out[#out + 1] = { text = word, col = col }
            i = j
        elseif c:match("%d") then
            local j = i
            while j <= n and line:sub(j, j):match("[%d%.xX]") do j = j + 1 end
            out[#out + 1] = { text = line:sub(i, j - 1), col = colors.cyan }
            i = j
        else
            out[#out + 1] = { text = c, col = colors.lightGray }
            i = i + 1
        end
    end
    return out
end

return function(args, ctx)
    if not args[2] then print("Использование: edit <файл>"); return 1 end
    local path = args[2]
    if not path:find("^/") then path = fs.combine(ctx.cwd, path) end
    local lines = {}
    if vfs.exists(path) and not vfs.isDir(path) then
        local data = vfs.read(path)
        for l in (data .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    end
    if #lines == 0 then lines[1] = "" end

    local w, h = term.getSize()
    local top = 1
    local row, col = 1, 1
    local th = theme.get()
    local dirty = false

    local function draw()
        term.setBackgroundColor(th.bg); term.clear()
        for i = 1, h - 1 do
            local li = top + i - 1
            local line = lines[li]
            if line then
                term.setCursorPos(1, i)
                term.setTextColor(colors.gray); term.write(string.format("%3d ", li))
                local tokens = highlight(line)
                for _, tk in ipairs(tokens) do
                    term.setTextColor(tk.col); term.write(tk.text)
                end
            end
        end
        term.setCursorPos(1, h)
        term.setBackgroundColor(colors.blue); term.setTextColor(colors.white)
        local status = (" " .. path .. (dirty and " *" or "") ..
            "  ^S=сохранить ^Q=выход  " .. row .. ":" .. col)
        term.write(status .. string.rep(" ", math.max(0, w - #status)))
        term.setCursorPos(math.min(w, 4 + col), row - top + 1)
        term.setCursorBlink(true)
        term.setBackgroundColor(th.bg)
    end

    draw()
    while true do
        local ev, p1, p2 = os.pullEvent()
        if ev == "char" then
            local l = lines[row]
            lines[row] = l:sub(1, col - 1) .. p1 .. l:sub(col)
            col = col + 1; dirty = true; draw()
        elseif ev == "key" then
            if p1 == keys.up and row > 1 then row = row - 1
                if row < top then top = row end
                col = math.min(col, #lines[row] + 1); draw()
            elseif p1 == keys.down and row < #lines then row = row + 1
                if row - top + 1 > h - 1 then top = top + 1 end
                col = math.min(col, #lines[row] + 1); draw()
            elseif p1 == keys.left and col > 1 then col = col - 1; draw()
            elseif p1 == keys.right and col <= #lines[row] then col = col + 1; draw()
            elseif p1 == keys.home then col = 1; draw()
            elseif p1 == keys["end"] then col = #lines[row] + 1; draw()
            elseif p1 == keys.enter then
                local l = lines[row]
                local tail = l:sub(col)
                lines[row] = l:sub(1, col - 1)
                table.insert(lines, row + 1, tail)
                row = row + 1; col = 1; dirty = true
                if row - top + 1 > h - 1 then top = top + 1 end
                draw()
            elseif p1 == keys.backspace then
                if col > 1 then
                    local l = lines[row]
                    lines[row] = l:sub(1, col - 2) .. l:sub(col)
                    col = col - 1; dirty = true; draw()
                elseif row > 1 then
                    col = #lines[row - 1] + 1
                    lines[row - 1] = lines[row - 1] .. lines[row]
                    table.remove(lines, row); row = row - 1; dirty = true; draw()
                end
            elseif p1 == keys.delete then
                local l = lines[row]
                if col <= #l then
                    lines[row] = l:sub(1, col - 1) .. l:sub(col + 1); dirty = true; draw()
                elseif lines[row + 1] then
                    lines[row] = l .. lines[row + 1]; table.remove(lines, row + 1)
                    dirty = true; draw()
                end
            elseif p1 == keys.leftCtrl or p1 == keys.rightCtrl then
                -- ждём следующую клавишу
                local _, k = os.pullEvent("key")
                if k == keys.s then
                    vfs.write(path, table.concat(lines, "\n"))
                    dirty = false; draw()
                elseif k == keys.q then
                    term.setCursorBlink(false)
                    term.setBackgroundColor(th.bg); term.clear(); term.setCursorPos(1, 1)
                    return 0
                end
            end
        end
    end
end
