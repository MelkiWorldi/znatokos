-- Тесты lib/layout.lua для ZnatokOS Browser.
-- Проверяем базовые случаи: текст, wrap, br, блоки, ссылки, заголовки, li, pre.

-- Попытка использовать фреймворк _T из OS. Если его нет — минимальная обёртка.
local T = _G._T
if not T then
    T = {}
    function T.assertEq(actual, expected, msg)
        if actual ~= expected then
            error(("assertEq failed: %s\n  expected: %s\n  actual:   %s")
                :format(tostring(msg or ""), tostring(expected), tostring(actual)), 2)
        end
    end
    function T.assertTrue(cond, msg)
        if not cond then
            error("assertTrue failed: " .. tostring(msg or ""), 2)
        end
    end
end

-- Загрузка модуля. В ZnatokOS — через znatokos.use, иначе require по relative path.
local layout
if _G.znatokos and _G.znatokos.use then
    layout = _G.znatokos.use("lib/layout")
else
    -- Позволяет запускать из корня пакета.
    package.path = package.path .. ";./?.lua;./lib/?.lua;./files/lib/?.lua"
    layout = require("layout")
end

-- ============================================================================
--  Хелперы для построения DOM вручную (эмуляция html.lua)
-- ============================================================================
local function elem(tag, attrs, children)
    return { kind = "elem", tag = tag, attrs = attrs or {}, children = children or {} }
end
local function text(t)
    return { kind = "text", text = t }
end

-- Ищет первый бокс с заданным type.
local function findFirst(boxes, boxType)
    for _, b in ipairs(boxes) do
        if b.type == boxType then return b end
    end
    return nil
end

-- Собирает все боксы с нужным type.
local function findAll(boxes, boxType)
    local r = {}
    for _, b in ipairs(boxes) do
        if b.type == boxType then r[#r+1] = b end
    end
    return r
end

-- ============================================================================
--  Тест 1: простой текст -> один text-бокс.
-- ============================================================================
do
    local dom = elem("body", {}, { text("Hello world") })
    local res = layout.compute(dom, 40)
    T.assertTrue(#res.boxes >= 1, "simple text: has boxes")
    local first = findFirst(res.boxes, "text")
    T.assertTrue(first ~= nil, "simple text: text box exists")
    T.assertEq(first.text, "Hello world", "simple text: content")
    T.assertEq(first.y, 1, "simple text: at y=1")
end

-- ============================================================================
--  Тест 2: wrap длинной строки -> несколько боксов на разных y.
-- ============================================================================
do
    local long = "один два три четыре пять шесть семь восемь девять десять"
    local dom = elem("body", {}, { text(long) })
    local res = layout.compute(dom, 15)
    local tboxes = findAll(res.boxes, "text")
    T.assertTrue(#tboxes >= 2, "wrap: multiple text boxes")
    -- Есть боксы на разных y.
    local ys = {}
    for _, b in ipairs(tboxes) do ys[b.y] = true end
    local count = 0
    for _ in pairs(ys) do count = count + 1 end
    T.assertTrue(count >= 2, "wrap: boxes on different y lines")
    -- Длина каждого бокса в символах не превышает ширину.
    for _, b in ipairs(tboxes) do
        T.assertTrue(layout._utf8Len(b.text) <= 15,
            "wrap: line <= width, got: " .. b.text)
    end
end

-- ============================================================================
--  Тест 3: <br> -> жёсткий разрыв.
-- ============================================================================
do
    local dom = elem("body", {}, {
        text("AAA"),
        elem("br"),
        text("BBB"),
    })
    local res = layout.compute(dom, 40)
    local tboxes = findAll(res.boxes, "text")
    T.assertTrue(#tboxes >= 2, "br: has 2 text boxes")
    -- Первый на y=1, второй на y=2.
    local a, b
    for _, box in ipairs(tboxes) do
        if box.text == "AAA" then a = box end
        if box.text == "BBB" then b = box end
    end
    T.assertTrue(a ~= nil and b ~= nil, "br: both texts present")
    T.assertTrue(b.y > a.y, "br: BBB below AAA")
end

-- ============================================================================
--  Тест 4: два <p> -> разные y.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("p", {}, { text("hello") }),
        elem("p", {}, { text("world") }),
    })
    local res = layout.compute(dom, 40)
    local tboxes = findAll(res.boxes, "text")
    local hy, wy
    for _, b in ipairs(tboxes) do
        if b.text == "hello" then hy = b.y end
        if b.text == "world" then wy = b.y end
    end
    T.assertTrue(hy ~= nil and wy ~= nil, "p: both found")
    T.assertTrue(wy > hy, "p: second paragraph below first")
end

-- ============================================================================
--  Тест 5: <a href=...> -> бокс type=link с href.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("a", { href = "http://example.com" }, { text("click") })
    })
    local res = layout.compute(dom, 40)
    local lbox = findFirst(res.boxes, "link")
    T.assertTrue(lbox ~= nil, "link: box exists")
    T.assertEq(lbox.text, "click", "link: text")
    T.assertEq(lbox.href, "http://example.com", "link: href set")
    T.assertTrue(lbox.style and lbox.style.underline == true, "link: underlined")
end

-- ============================================================================
--  Тест 6: <h1> и <h2> имеют разные fg.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("h1", {}, { text("Big") }),
        elem("h2", {}, { text("Small") }),
    })
    local res = layout.compute(dom, 40)
    local big, small
    for _, b in ipairs(res.boxes) do
        if b.text == "Big" then big = b end
        if b.text == "Small" then small = b end
    end
    T.assertTrue(big ~= nil and small ~= nil, "headings: both found")
    T.assertTrue(big.style.fg ~= small.style.fg, "headings: different fg")
end

-- ============================================================================
--  Тест 7: <li> имеет маркер "* ".
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("ul", {}, {
            elem("li", {}, { text("item1") }),
            elem("li", {}, { text("item2") }),
        })
    })
    local res = layout.compute(dom, 40)
    -- Ищем бокс с текстом, начинающимся на "* ".
    local found = false
    for _, b in ipairs(res.boxes) do
        if b.text and b.text:sub(1, 2) == "* " then found = true break end
    end
    T.assertTrue(found, "li: marker '* ' present")
end

-- ============================================================================
--  Тест 7b: <ol> нумерует li.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("ol", {}, {
            elem("li", {}, { text("a") }),
            elem("li", {}, { text("b") }),
        })
    })
    local res = layout.compute(dom, 40)
    local saw1, saw2 = false, false
    for _, b in ipairs(res.boxes) do
        if b.text == "1. " then saw1 = true end
        if b.text == "2. " then saw2 = true end
    end
    T.assertTrue(saw1 and saw2, "ol: numbered markers '1. ' and '2. '")
end

-- ============================================================================
--  Тест 8: <pre> сохраняет переносы.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("pre", {}, { text("line1\nline2\nline3") }),
    })
    local res = layout.compute(dom, 40)
    local tboxes = findAll(res.boxes, "text")
    local ys = {}
    for _, b in ipairs(tboxes) do
        if b.text == "line1" or b.text == "line2" or b.text == "line3" then
            ys[b.text] = b.y
        end
    end
    T.assertTrue(ys.line1 and ys.line2 and ys.line3, "pre: all 3 lines present")
    T.assertTrue(ys.line2 > ys.line1, "pre: line2 below line1")
    T.assertTrue(ys.line3 > ys.line2, "pre: line3 below line2")
end

-- ============================================================================
--  Тест 9: <hr> производит бокс type="hr".
-- ============================================================================
do
    local dom = elem("body", {}, { elem("hr") })
    local res = layout.compute(dom, 20)
    local hr = findFirst(res.boxes, "hr")
    T.assertTrue(hr ~= nil, "hr: box present")
    T.assertEq(hr.w, 20, "hr: full width")
end

-- ============================================================================
--  Тест 10: <img alt="X"> -> placeholder.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("img", { alt = "logo", src = "x.png" }),
    })
    local res = layout.compute(dom, 40)
    local img = findFirst(res.boxes, "img_placeholder")
    T.assertTrue(img ~= nil, "img: placeholder present")
    T.assertTrue(img.text:find("logo") ~= nil, "img: alt in text")
    T.assertEq(img.alt, "logo", "img: alt field set")
end

-- ============================================================================
--  Тест 11: <input> -> input-бокс.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("input", { type = "text", name = "q", value = "hi", size = 10 }),
    })
    local res = layout.compute(dom, 40)
    local inp = findFirst(res.boxes, "input")
    T.assertTrue(inp ~= nil, "input: box present")
    T.assertEq(inp.name, "q", "input: name")
    T.assertEq(inp.value, "hi", "input: value")
    T.assertEq(inp.inputType, "text", "input: inputType")
end

-- ============================================================================
--  Тест 12: <button>text</button> -> button-бокс с label.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("button", { name = "go" }, { text("Go!") }),
    })
    local res = layout.compute(dom, 40)
    local btn = findFirst(res.boxes, "button")
    T.assertTrue(btn ~= nil, "button: box present")
    T.assertTrue(btn.text:find("Go!") ~= nil, "button: label included")
    T.assertEq(btn.name, "go", "button: name")
end

-- ============================================================================
--  Тест 13: script/style игнорируются.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("script", {}, { text("alert(1)") }),
        elem("style", {}, { text("body{}") }),
        text("visible"),
    })
    local res = layout.compute(dom, 40)
    for _, b in ipairs(res.boxes) do
        T.assertTrue(b.text ~= "alert(1)", "ignored: script text not rendered")
        T.assertTrue(b.text ~= "body{}", "ignored: style text not rendered")
    end
    local vis = false
    for _, b in ipairs(res.boxes) do
        if b.text == "visible" then vis = true end
    end
    T.assertTrue(vis, "ignored: visible text present")
end

-- ============================================================================
--  Тест 14: множественные пробелы коллапсируются (white-space: normal).
-- ============================================================================
do
    local dom = elem("body", {}, { text("a   b\n\n\t c") })
    local res = layout.compute(dom, 40)
    -- Должен получиться текст "a b c" (возможно в нескольких боксах).
    local full = ""
    for _, b in ipairs(findAll(res.boxes, "text")) do
        full = full .. b.text
    end
    T.assertEq(full, "a b c", "whitespace normalization")
end

-- ============================================================================
--  Тест 15: totalHeight растёт с количеством строк.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("p", {}, { text("one") }),
        elem("p", {}, { text("two") }),
        elem("p", {}, { text("three") }),
    })
    local res = layout.compute(dom, 40)
    T.assertTrue(res.totalHeight >= 3, "totalHeight: at least 3 rows")
end

-- ============================================================================
--  Тест 16: utf8Len работает на кириллице.
-- ============================================================================
do
    T.assertEq(layout._utf8Len(""), 0, "utf8Len: empty")
    T.assertEq(layout._utf8Len("abc"), 3, "utf8Len: ascii")
    T.assertEq(layout._utf8Len("Привет"), 6, "utf8Len: cyrillic")
end

-- ============================================================================
--  Тест 17: ссылка внутри параграфа -> link-бокс с href.
-- ============================================================================
do
    local dom = elem("body", {}, {
        elem("p", {}, {
            text("see "),
            elem("a", { href = "/foo" }, { text("this") }),
            text(" now"),
        }),
    })
    local res = layout.compute(dom, 40)
    local lbox = findFirst(res.boxes, "link")
    T.assertTrue(lbox ~= nil, "inline link: box found")
    T.assertEq(lbox.href, "/foo", "inline link: href")
    T.assertEq(lbox.text, "this", "inline link: text")
end

if _G.print then print("test_layout: all assertions passed") end
