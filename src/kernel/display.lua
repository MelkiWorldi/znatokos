-- Управление дисплеем CC:Tweaked: единая виртуальная плоскость из
-- произвольного числа «групп мониторов». Группа = одиночный монитор,
-- merged-monitor, либо тайлинг N×M отдельных мониторов.
--
-- Плоскость = Redirect-объект с неравномерной сеткой regions. Каждый
-- region имеет rect на плоскости и свою terminal-цель.
--
-- Конфиг: /znatokos/etc/display.cfg
--   {
--     plane = {
--       { at = {x=1, y=1},  kind = "tile",
--         cols=4, rows=3, monitors = {"monitor_0",...} },
--       { at = {x=29, y=1}, kind = "single", peripheral = "monitor_12" },
--     },
--     mirror_builtin = true,
--   }
local log   = znatokos.use("kernel/log")
local paths = znatokos.use("fs/paths")

local M = {}
local builtinTerm = term.current()
local currentAdapter = nil

--------------------------------------------------------------
-- mirror (primary + secondary): для mirror_builtin = true
--------------------------------------------------------------
local function makeMirrorTerm(primary, secondary)
    local t = {}
    for name, fn in pairs(primary) do
        if type(fn) == "function" then
            t[name] = function(...)
                local r = table.pack(primary[name](...))
                pcall(secondary[name], ...)
                return table.unpack(r, 1, r.n)
            end
        end
    end
    return t
end

--------------------------------------------------------------
-- tile: сетка N×M отдельных одинаковых мониторов
--------------------------------------------------------------
local function buildTileRegion(cols, rows, monitors)
    for _, m in ipairs(monitors) do pcall(m.setTextScale, 0.5) end
    local tileW, tileH = monitors[1].getSize()
    local totalW, totalH = tileW * cols, tileH * rows
    local function locate(lx, ly)
        if lx < 1 or lx > totalW or ly < 1 or ly > totalH then return nil end
        local col = math.floor((lx - 1) / tileW)
        local row = math.floor((ly - 1) / tileH)
        return monitors[row * cols + col + 1],
               ((lx - 1) % tileW) + 1, ((ly - 1) % tileH) + 1
    end
    return {
        w = totalW, h = totalH,
        monitors = monitors,
        locate = locate,
        forEach = function(fn) for _, m in ipairs(monitors) do fn(m) end end,
    }
end

--------------------------------------------------------------
-- single / merged: один peripheral-monitor (CC auto-merged если смежные)
--------------------------------------------------------------
local function buildSingleRegion(mon)
    pcall(mon.setTextScale, 0.5)
    local w, h = mon.getSize()
    return {
        w = w, h = h,
        monitors = { mon },
        locate = function(lx, ly)
            if lx < 1 or lx > w or ly < 1 or ly > h then return nil end
            return mon, lx, ly
        end,
        forEach = function(fn) fn(mon) end,
    }
end

--------------------------------------------------------------
-- plane-adapter: Redirect, покрывающий всю виртуальную плоскость
--------------------------------------------------------------
local function makePlaneAdapter(regions)
    -- plane size = bounding box всех regions
    local maxX, maxY = 0, 0
    for _, r in ipairs(regions) do
        local rx, ry = r.at.x, r.at.y
        if rx + r.region.w - 1 > maxX then maxX = rx + r.region.w - 1 end
        if ry + r.region.h - 1 > maxY then maxY = ry + r.region.h - 1 end
    end

    local cx, cy = 1, 1
    local fg, bg = colors.white, colors.black
    local blinkOn = false

    -- Найти region под планетарной координатой (gx, gy) → region, localX, localY
    local function planeLocate(gx, gy)
        for _, r in ipairs(regions) do
            local lx = gx - r.at.x + 1
            local ly = gy - r.at.y + 1
            if lx >= 1 and lx <= r.region.w and ly >= 1 and ly <= r.region.h then
                local mon, mlx, mly = r.region.locate(lx, ly)
                if mon then return mon, mlx, mly end
            end
        end
        return nil
    end

    local t = {}

    function t.write(s)
        s = tostring(s or "")
        for i = 1, #s do
            local mon, lx, ly = planeLocate(cx, cy)
            if mon then
                mon.setCursorPos(lx, ly)
                mon.setTextColor(fg); mon.setBackgroundColor(bg)
                mon.write(s:sub(i, i))
            end
            cx = cx + 1
        end
    end
    function t.blit(s, fgs, bgs)
        for i = 1, #s do
            local mon, lx, ly = planeLocate(cx, cy)
            if mon then
                mon.setCursorPos(lx, ly)
                mon.blit(s:sub(i, i), fgs:sub(i, i), bgs:sub(i, i))
            end
            cx = cx + 1
        end
    end
    function t.setCursorPos(x, y)
        cx, cy = x, y
        local mon, lx, ly = planeLocate(x, y)
        if mon then mon.setCursorPos(lx, ly) end
    end
    function t.getCursorPos() return cx, cy end
    function t.getSize() return maxX, maxY end
    function t.setTextColor(c)
        fg = c; for _, r in ipairs(regions) do r.region.forEach(function(m) m.setTextColor(c) end) end
    end
    t.setTextColour = t.setTextColor
    function t.setBackgroundColor(c)
        bg = c; for _, r in ipairs(regions) do r.region.forEach(function(m) m.setBackgroundColor(c) end) end
    end
    t.setBackgroundColour = t.setBackgroundColor
    function t.getTextColor() return fg end
    t.getTextColour = t.getTextColor
    function t.getBackgroundColor() return bg end
    t.getBackgroundColour = t.getBackgroundColor
    function t.clear()
        for _, r in ipairs(regions) do r.region.forEach(function(m) m.clear() end) end
    end
    function t.clearLine()
        -- очистим полосу y = cy на всех regions, которые её покрывают
        for gx = 1, maxX do
            local mon, lx, ly = planeLocate(gx, cy)
            if mon then
                mon.setCursorPos(lx, ly)
                mon.setBackgroundColor(bg); mon.write(" ")
            end
        end
    end
    function t.setCursorBlink(b)
        blinkOn = b
        local mon = planeLocate(cx, cy); if mon then mon.setCursorBlink(b) end
    end
    function t.isColor() return regions[1].region.monitors[1].isColor() end
    t.isColour = t.isColor
    function t.scroll(n)
        for _, r in ipairs(regions) do r.region.forEach(function(m) m.scroll(n) end) end
    end
    function t.setPaletteColor(c, r2, g, b2)
        for _, r in ipairs(regions) do r.region.forEach(function(m)
            if m.setPaletteColor then pcall(m.setPaletteColor, c, r2, g, b2) end
        end) end
    end
    t.setPaletteColour = t.setPaletteColor
    function t.getPaletteColor(c)
        local m = regions[1].region.monitors[1]
        return m.getPaletteColor and m.getPaletteColor(c)
    end
    t.getPaletteColour = t.getPaletteColor
    function t.redirect(x) return x end

    return t
end

--------------------------------------------------------------
-- конфиг
--------------------------------------------------------------
local CFG_PATH = paths.ETC .. "/display.cfg"

function M.loadConfig()
    if not fs.exists(CFG_PATH) then return nil end
    local fn = loadfile(CFG_PATH); if not fn then return nil end
    local ok, v = pcall(fn)
    return ok and v or nil
end

function M.saveConfig(cfg)
    if not fs.exists(paths.ETC) then fs.makeDir(paths.ETC) end
    local f = fs.open(CFG_PATH, "w")
    f.write("return " .. textutils.serialize(cfg)); f.close()
end

local function wrapPeripheral(name)
    if not name then return nil end
    return peripheral.wrap(name)
end

local function wrapNames(names)
    local w = {}
    for i, n in ipairs(names) do
        w[i] = wrapPeripheral(n)
        if not w[i] then
            log.error("display: нет периферии " .. n)
            return nil
        end
    end
    return w
end

--------------------------------------------------------------
-- сборка plane по конфигу
--------------------------------------------------------------
local function buildPlane(cfg)
    local regions = {}
    for _, g in ipairs(cfg.plane or {}) do
        local reg
        if g.kind == "tile" then
            local mons = wrapNames(g.monitors)
            if not mons or #mons ~= g.cols * g.rows then
                log.error("display: tile: требуется " .. (g.cols * g.rows) .. " мониторов")
                return nil
            end
            reg = buildTileRegion(g.cols, g.rows, mons)
        elseif g.kind == "single" or g.kind == "merged" then
            local m = wrapPeripheral(g.peripheral)
            if not m then
                log.error("display: нет " .. tostring(g.peripheral))
                return nil
            end
            reg = buildSingleRegion(m)
        else
            log.error("display: неизвестный kind " .. tostring(g.kind))
            return nil
        end
        regions[#regions + 1] = { at = g.at or {x=1,y=1}, region = reg }
    end
    if #regions == 0 then return nil end
    return makePlaneAdapter(regions), regions
end

--------------------------------------------------------------
-- основной запуск
--------------------------------------------------------------
function M.start()
    if not peripheral then return false end
    local cfg = M.loadConfig()
    local adapter

    if cfg and cfg.plane and #cfg.plane > 0 then
        local planeTerm, regions = buildPlane(cfg)
        if planeTerm then
            local mirror = planeTerm
            if cfg.mirror_builtin then
                mirror = makeMirrorTerm(planeTerm, builtinTerm)
            end
            adapter = { term = mirror, kind = "plane", regions = regions }
            log.info(("display: plane, %d groups"):format(#regions))
        end
    end

    if not adapter then
        local mon = peripheral.find("monitor")
        if mon then
            pcall(mon.setTextScale, 0.5)
            local mirror = makeMirrorTerm(mon, builtinTerm)
            adapter = { term = mirror, kind = "single" }
            local w, h = mon.getSize()
            log.info(("display: single monitor %dx%d"):format(w, h))
        else
            return false
        end
    end

    currentAdapter = adapter
    term.redirect(adapter.term)
    local sched_ok, sched = pcall(znatokos.use, "kernel/scheduler")
    if sched_ok and sched.setNativeTerm then sched.setNativeTerm(adapter.term) end
    local wm_ok, wm = pcall(znatokos.use, "kernel/window")
    if wm_ok and wm.setParent then wm.setParent(adapter.term) end
    return true, adapter.kind
end

function M.current() return currentAdapter and currentAdapter.term or builtinTerm end
function M.kind() return currentAdapter and currentAdapter.kind or "builtin" end

function M.onPeripheralEvent(event, side)
    -- hot-plug: посылаем znatokos:resize чтобы UI перерисовался
    -- (реконфигурация plane требует reboot — это tech-debt)
    os.queueEvent("znatokos:resize")
end

function M.listAllMonitors()
    if not peripheral then return {} end
    local out = {}
    for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == "monitor" then out[#out + 1] = n end
    end
    return out
end

return M
