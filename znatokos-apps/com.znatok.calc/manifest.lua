-- Манифест приложения «Калькулятор» для ZnatokOS v0.3.0
return {
    id = "com.znatok.calc",
    name = "Калькулятор",
    version = "1.0.0",
    author = "znatok",
    description = "Арифметический калькулятор",
    icon = { color = colors.orange, glyph = "=" },
    entry = "main.lua",
    files = { "main.lua" },
    capabilities = { "ui.window" },
    min_os_version = "0.3.0",
    deps = {},
}
