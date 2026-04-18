-- Манифест приложения Paint для ZnatokOS v0.3.0
return {
    id = "com.znatok.paint",
    name = "Paint",
    version = "1.0.0",
    author = "znatok",
    description = "Рисование цветными пикселями в окне",
    icon = { color = colors.pink, glyph = "P" },
    entry = "main.lua",
    files = { "main.lua" },
    capabilities = { "ui.window", "fs.home" },
    min_os_version = "0.3.0",
    deps = {},
}
