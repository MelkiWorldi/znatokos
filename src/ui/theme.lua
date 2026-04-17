-- Темы оформления. Читает /znatokos/etc/theme.lua если есть, иначе — default.
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

function M.get() return THEMES[current] end
function M.name() return current end
function M.listNames()
    local arr = {}
    for k in pairs(THEMES) do arr[#arr + 1] = k end
    table.sort(arr)
    return arr
end

function M.set(name)
    if not THEMES[name] then return false end
    current = name
    local dir = fs.getDir(paths.THEME)
    if not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(paths.THEME, "w")
    f.write("return " .. string.format("%q", name))
    f.close()
    return true
end

return M
