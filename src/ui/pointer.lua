-- Видимый курсор-указатель. Активируется через настройки.
-- Стрелки двигают, Shift+стрелка = прыжок на 5, Enter = ЛКМ, Shift+Enter = ПКМ.
-- Автоматически прячется при реальном mouse_click.
local paths = znatokos.use("fs/paths")

local M = {}
local enabled = false
local visible = false
local px, py = 1, 1
local savedFg, savedBg, savedCh = nil, nil, nil

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
    enabled = v
    if not fs.exists(paths.ETC) then fs.makeDir(paths.ETC) end
    local f = fs.open(CFG_PATH, "w")
    f.write(v and "true" or "false"); f.close()
    if not v then M.hide() end
end

local function drawPointer()
    local w, h = term.getSize()
    px = math.max(1, math.min(w, px))
    py = math.max(1, math.min(h, py))
    term.setCursorPos(px, py)
    term.setBackgroundColor(colors.yellow)
    term.setTextColor(colors.black)
    term.write(">")
    visible = true
end

function M.show()
    if not M.isEnabled() then return end
    drawPointer()
end

function M.hide()
    visible = false
end

function M.moveBy(dx, dy)
    if not M.isEnabled() then return end
    px = px + dx; py = py + dy
    drawPointer()
end

function M.moveTo(x, y)
    px, py = x, y
    if M.isEnabled() then drawPointer() end
end

function M.position() return px, py end

-- Активация: генерирует mouse_click в текущей позиции
function M.activate(button)
    os.queueEvent("mouse_click", button or 1, px, py)
end

-- Обработчик клавиш. Возвращает true если событие обработано.
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
    -- реальный клик мышью — прячем указатель
    if M.isEnabled() then M.hide() end
end

return M
