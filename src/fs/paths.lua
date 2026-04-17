-- Константы путей ЗнатокOS
local ROOT = "/znatokos"
return {
    ROOT     = ROOT,
    SRC      = ROOT .. "/src",
    ETC      = ROOT .. "/etc",
    VAR      = ROOT .. "/var",
    LOG      = ROOT .. "/var/log/system.log",
    PASSWD   = ROOT .. "/etc/passwd",
    THEME    = ROOT .. "/etc/theme.lua",
    CONFIG   = ROOT .. "/etc/znatokos.cfg",
    HOMES    = "/home",
    TMP      = ROOT .. "/var/tmp",
    PKG_DIR  = ROOT .. "/var/pkg",
    PKG_DB   = ROOT .. "/var/pkg/installed.db",
    APPS     = ROOT .. "/src/apps",
    COMMANDS = ROOT .. "/src/shell/commands",
    MANIFEST = ROOT .. "/manifest.lua",
}
