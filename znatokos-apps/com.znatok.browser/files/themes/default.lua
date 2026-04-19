-- themes/default.lua — дефолтная цветовая тема браузера ZnatokOS.
-- Это ВНУТРЕННЯЯ тема браузер-приложения (не путать с ui/theme в OS).
-- Используется рендером как fallback, когда CSS-стили не заданы.

return {
    -- Основные цвета интерфейса
    bg          = colors.black,
    fg          = colors.white,

    -- Chrome (адресная строка, кнопки навигации)
    chrome_bg   = colors.gray,
    chrome_fg   = colors.white,
    accent      = colors.lime,

    -- Статус-строка
    status_bg   = colors.lightGray,
    status_fg   = colors.black,

    -- Вкладки
    tab_active_bg   = colors.white,
    tab_active_fg   = colors.black,
    tab_inactive_bg = colors.gray,
    tab_inactive_fg = colors.lightGray,

    -- Контент страницы (fallback, если CSS не применился)
    link_fg         = colors.lightBlue,
    visited_fg      = colors.purple,
    button_bg       = colors.lime,
    button_fg       = colors.black,
    input_bg        = colors.gray,
    input_fg        = colors.white,
    error_fg        = colors.red,

    -- Заголовки по уровню (fallback)
    h1_fg           = colors.yellow,
    h2_fg           = colors.orange,
    h3_fg           = colors.orange,
}
