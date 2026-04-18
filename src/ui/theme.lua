-- Темы. Каждая тема — таблица полей + опциональная palette (rgb override).
-- При активации применяется setPaletteColor на все переопределения.
local paths = znatokos.use("fs/paths")

local M = {}

local THEMES = {
    classic = {
        name = "classic",
        bg = colors.black, fg = colors.white,
        desktop = colors.cyan,
        title_bg = colors.blue, title_bg_inactive = colors.gray, title_fg = colors.white,
        accent = colors.yellow,
        btn_bg = colors.lightGray, btn_fg = colors.black,
        btn_active_bg = colors.yellow, btn_active_fg = colors.black,
        taskbar_bg = colors.gray, taskbar_fg = colors.white,
        menu_bg = colors.lightGray, menu_fg = colors.black,
        selection_bg = colors.blue, selection_fg = colors.white,
        error = colors.red, ok = colors.lime, warn = colors.orange,
        palette = nil,
    },
    dark = {
        name = "dark",
        bg = colors.black, fg = colors.lightGray,
        desktop = colors.gray,
        title_bg = colors.purple, title_bg_inactive = colors.gray, title_fg = colors.white,
        accent = colors.magenta,
        btn_bg = colors.gray, btn_fg = colors.white,
        btn_active_bg = colors.magenta, btn_active_fg = colors.white,
        taskbar_bg = colors.black, taskbar_fg = colors.lightGray,
        menu_bg = colors.gray, menu_fg = colors.white,
        selection_bg = colors.purple, selection_fg = colors.white,
        error = colors.red, ok = colors.lime, warn = colors.orange,
        palette = nil,
    },
    solarized = {
        name = "solarized",
        bg = colors.lightGray, fg = colors.blue,
        desktop = colors.yellow,
        title_bg = colors.orange, title_bg_inactive = colors.brown, title_fg = colors.white,
        accent = colors.orange,
        btn_bg = colors.white, btn_fg = colors.blue,
        btn_active_bg = colors.orange, btn_active_fg = colors.white,
        taskbar_bg = colors.brown, taskbar_fg = colors.white,
        menu_bg = colors.white, menu_fg = colors.blue,
        selection_bg = colors.cyan, selection_fg = colors.white,
        error = colors.red, ok = colors.green, warn = colors.orange,
        palette = {
            [colors.lightGray] = 0xeee8d5,  -- solarized base2
            [colors.yellow]    = 0xb58900,
            [colors.orange]    = 0xcb4b16,
            [colors.blue]      = 0x073642,  -- base03
            [colors.brown]     = 0x586e75,  -- base01
            [colors.white]     = 0xfdf6e3,  -- base3
            [colors.cyan]      = 0x2aa198,
        },
    },
    midnight = {
        name = "midnight",
        bg = colors.black, fg = colors.white,
        desktop = colors.blue,
        title_bg = colors.cyan, title_bg_inactive = colors.gray, title_fg = colors.black,
        accent = colors.lime,
        btn_bg = colors.lightGray, btn_fg = colors.black,
        btn_active_bg = colors.lime, btn_active_fg = colors.black,
        taskbar_bg = colors.black, taskbar_fg = colors.white,
        menu_bg = colors.gray, menu_fg = colors.white,
        selection_bg = colors.cyan, selection_fg = colors.black,
        error = colors.red, ok = colors.lime, warn = colors.orange,
        palette = {
            [colors.blue] = 0x0a1a3a,
            [colors.cyan] = 0x4a9eff,
        },
    },
}

local current = "classic"

local function load()
    if fs.exists(paths.THEME) then
        local fn = loadfile(paths.THEME)
        if fn then
            local ok, name = pcall(fn)
            if ok and type(name) == "string" and THEMES[name] then
                current = name
            end
        end
    end
end
load()

-- Применить/сбросить палитру темы
local function applyPalette(theme)
    if not term.setPaletteColor then return end
    if theme.palette then
        for slot, rgb in pairs(theme.palette) do
            pcall(term.setPaletteColor, slot, rgb)
        end
    end
end

local function resetPalette()
    if not term.nativePaletteColor or not term.setPaletteColor then return end
    for _, c in pairs(colors) do
        if type(c) == "number" then
            local r, g, b = term.nativePaletteColor(c)
            pcall(term.setPaletteColor, c, r, g, b)
        end
    end
end

function M.get() return THEMES[current] end
function M.name() return current end
function M.listNames()
    local arr = {}
    for k in pairs(THEMES) do arr[#arr + 1] = k end
    table.sort(arr); return arr
end

function M.set(name)
    if not THEMES[name] then return false end
    resetPalette()
    current = name
    applyPalette(THEMES[name])
    local dir = fs.getDir(paths.THEME)
    if not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(paths.THEME, "w")
    f.write("return " .. string.format("%q", name)); f.close()
    return true
end

function M.applyCurrent()
    applyPalette(THEMES[current])
end

return M
