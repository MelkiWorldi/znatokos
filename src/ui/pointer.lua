-- Видимый курсор-указатель. Сохраняет клетку под собой через term/window:getLine
-- (если доступно) или простую перерисовку. Стрелки двигают, Enter = ЛКМ,
-- Shift+Enter = ПКМ.
local paths = znatokos.use("fs/paths")

local M = {}
local enabled = nil    -- nil = не загружено, false/true после loadEnabled
local visible = false
local px, py = 1, 1
-- Сохранённая клетка: { ch, fg, bg }
local saved = nil

local CFG_PATH = paths.ETC .. "/pointer.cfg"

local function loadEnabled()
    if not fs.exists(CFG_PATH) then return false end
    local f = fs.open(CFG_PATH, "r"); local v = f.readAll(); f.close()
    return v:match("true") ~= nil
end

function M.isEnabled()
    if enabled == nil then enabled = loadEnabled() end
    return enabled
end

function M.setEnabled(v)
    if v then enabled = true else enabled = false end
    if not fs.exists(paths.ETC) then fs.makeDir(paths.ETC) end
    local f = fs.open(CFG_PATH, "w")
    f.write(enabled and "true" or "false"); f.close()
    if not enabled then M.hide() end
end

-- Сохранить ту клетку, куда собираемся рисовать курсор.
local function captureCell(x, y)
    local cur = term.current()
    if cur.getLine then
        local line, fg, bg = cur.getLine(y)
        if line then
            local ch = line:sub(x, x)
            local fc = tonumber(fg and fg:sub(x, x) or "0", 16) or 0
            local bc = tonumber(bg and bg:sub(x, x) or "f", 16) or 0
            saved = {
                ch = ch ~= "" and ch or " ",
                fg = 2 ^ fc,
                bg = 2 ^ bc,
            }
            return
        end
    end
    saved = { ch = " ", fg = colors.white, bg = colors.black }
end

local function restoreCell()
    if not saved or not visible then return end
    local cur = term.current()
    local w, h = cur.getSize()
    if px >= 1 and px <= w and py >= 1 and py <= h then
        local oldFg = cur.getTextColor and cur.getTextColor() or colors.white
        local oldBg = cur.getBackgroundColor and cur.getBackgroundColor() or colors.black
        cur.setTextColor(saved.fg); cur.setBackgroundColor(saved.bg)
        cur.setCursorPos(px, py); cur.write(saved.ch)
        cur.setTextColor(oldFg); cur.setBackgroundColor(oldBg)
    end
    saved = nil
end

local function drawPointer()
    local cur = term.current()
    local w, h = cur.getSize()
    px = math.max(1, math.min(w, px))
    py = math.max(1, math.min(h, py))
    restoreCell()
    captureCell(px, py)
    local oldFg = cur.getTextColor and cur.getTextColor() or colors.white
    local oldBg = cur.getBackgroundColor and cur.getBackgroundColor() or colors.black
    cur.setBackgroundColor(colors.yellow); cur.setTextColor(colors.black)
    cur.setCursorPos(px, py); cur.write(">")
    cur.setTextColor(oldFg); cur.setBackgroundColor(oldBg)
    visible = true
end

function M.show()
    if not M.isEnabled() then return end
    drawPointer()
end

function M.hide()
    if visible then restoreCell() end
    visible = false
end

function M.moveBy(dx, dy)
    if not M.isEnabled() then return end
    restoreCell()
    px = px + dx; py = py + dy
    drawPointer()
end

function M.moveTo(x, y)
    restoreCell(); px, py = x, y
    if M.isEnabled() then drawPointer() end
end

function M.position() return px, py end

function M.activate(button)
    os.queueEvent("mouse_click", button or 1, px, py)
end

function M.handleKey(key, shiftHeld)
    if not M.isEnabled() then return false end
    local step = shiftHeld and 5 or 1
    if key == keys.up then M.moveBy(0, -step); return true
    elseif key == keys.down then M.moveBy(0, step); return true
    elseif key == keys.left then M.moveBy(-step, 0); return true
    elseif key == keys.right then M.moveBy(step, 0); return true
    elseif key == keys.enter then
        M.activate(shiftHeld and 2 or 1); return true
    end
    return false
end

function M.onMouseClick()
    if M.isEnabled() then M.hide() end
end

return M
