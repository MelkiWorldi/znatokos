return {
    id = "com.znatok.chat",
    name = "Чат",
    version = "1.0.0",
    author = "znatok",
    description = "Чат через rednet в локальной сети ZnatokOS",
    icon = { color = colors.magenta, glyph = "M" },
    entry = "main.lua",
    files = { "main.lua" },
    capabilities = { "ui.window", "net.rednet" },
    min_os_version = "0.3.0",
    deps = {},
}
