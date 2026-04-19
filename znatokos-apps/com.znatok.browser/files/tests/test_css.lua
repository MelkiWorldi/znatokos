-- test_css.lua
-- Тесты для CSS-парсера lib/css.lua.
-- Запуск:
--   lua tests/test_css.lua

package.path = package.path
    .. ";./lib/?.lua;../lib/?.lua;./files/lib/?.lua"

-- Стаб для глобала `colors` (в CC:Tweaked он приходит от системы).
-- Используем битовые маски в духе оригинальной палитры.
_G.colors = {
    white     = 0x1,
    orange    = 0x2,
    magenta   = 0x4,
    lightBlue = 0x8,
    yellow    = 0x10,
    lime      = 0x20,
    pink      = 0x40,
    gray      = 0x80,
    lightGray = 0x100,
    cyan      = 0x200,
    purple    = 0x400,
    blue      = 0x800,
    brown     = 0x1000,
    green     = 0x2000,
    red       = 0x4000,
    black     = 0x8000,
}

local css = require("css")

-- -----------------------------------------------------------------------
-- Мини-фреймворк.
-- -----------------------------------------------------------------------

local tests_run, tests_fail = 0, 0
local failed_names = {}

local function test(name, fn)
    tests_run = tests_run + 1
    local ok, err = pcall(fn)
    if not ok then
        tests_fail = tests_fail + 1
        failed_names[#failed_names + 1] = name
        print("[FAIL] " .. name .. ": " .. tostring(err))
    else
        print("[ OK ] " .. name)
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "assert_eq failed")
            .. " | got=" .. tostring(a)
            .. " expected=" .. tostring(b), 2)
    end
end

local function assert_true(v, msg)
    if not v then error(msg or "assert_true failed", 2) end
end

local function assert_nil(v, msg)
    if v ~= nil then
        error((msg or "assert_nil failed") .. " | got=" .. tostring(v), 2)
    end
end

-- -----------------------------------------------------------------------
-- hexToRgb / rgbToCC
-- -----------------------------------------------------------------------

test("hexToRgb: #rrggbb", function()
    local r, g, b = css.hexToRgb("#ff8800")
    assert_eq(r, 255); assert_eq(g, 136); assert_eq(b, 0)
end)

test("hexToRgb: #rgb shorthand", function()
    local r, g, b = css.hexToRgb("#f80")
    assert_eq(r, 255); assert_eq(g, 136); assert_eq(b, 0)
end)

test("hexToRgb: мусор -> nil", function()
    assert_nil(css.hexToRgb("not-a-color"))
end)

test("rgbToCC: чёрный", function()
    assert_eq(css.rgbToCC(0, 0, 0), colors.black)
end)

test("rgbToCC: белый", function()
    assert_eq(css.rgbToCC(255, 255, 255), colors.white)
end)

test("rgbToCC: красный", function()
    assert_eq(css.rgbToCC(255, 0, 0), colors.red)
end)

test("rgbToCC: синий", function()
    assert_eq(css.rgbToCC(0, 0, 255), colors.blue)
end)

test("rgbToCC: зелёный", function()
    assert_eq(css.rgbToCC(0, 255, 0), colors.lime)
end)

-- -----------------------------------------------------------------------
-- parseInline
-- -----------------------------------------------------------------------

test("parseInline: color: red", function()
    local s = css.parseInline("color: red")
    assert_eq(s.fg, colors.red)
end)

test("parseInline: color: #ff0000 -> red", function()
    local s = css.parseInline("color: #ff0000")
    assert_eq(s.fg, colors.red)
end)

test("parseInline: color: #f00 -> red", function()
    local s = css.parseInline("color: #f00")
    assert_eq(s.fg, colors.red)
end)

test("parseInline: font-weight: bold + color: blue", function()
    local s = css.parseInline("font-weight: bold; color: blue")
    assert_eq(s.bold, true)
    assert_eq(s.fg, colors.blue)
end)

test("parseInline: background-color: yellow", function()
    local s = css.parseInline("background-color: yellow")
    assert_eq(s.bg, colors.yellow)
end)

test("parseInline: background: green (shorthand)", function()
    local s = css.parseInline("background: green")
    assert_eq(s.bg, colors.green)
end)

test("parseInline: text-decoration: underline", function()
    local s = css.parseInline("text-decoration: underline")
    assert_eq(s.underline, true)
end)

test("parseInline: text-decoration: line-through -> strike", function()
    local s = css.parseInline("text-decoration: line-through")
    assert_eq(s.strike, true)
end)

test("parseInline: font-style: italic", function()
    local s = css.parseInline("font-style: italic")
    assert_eq(s.italic, true)
end)

test("parseInline: display: none -> hidden", function()
    local s = css.parseInline("display: none")
    assert_eq(s.hidden, true)
end)

test("parseInline: неизвестные свойства не падают", function()
    local s = css.parseInline(
        "font-size: 14px; margin: 10px; padding: 5px; width: 100%;"
    )
    -- Никаких полей не должно появиться.
    assert_nil(s.fg); assert_nil(s.bg); assert_nil(s.bold)
end)

test("parseInline: пустая строка", function()
    local s = css.parseInline("")
    assert_eq(next(s), nil)
end)

test("parseInline: font-weight 700 -> bold", function()
    local s = css.parseInline("font-weight: 700")
    assert_eq(s.bold, true)
end)

test("parseInline: rgb(255,0,0) -> red", function()
    local s = css.parseInline("color: rgb(255, 0, 0)")
    assert_eq(s.fg, colors.red)
end)

-- -----------------------------------------------------------------------
-- parseStyleBlock
-- -----------------------------------------------------------------------

test("parseStyleBlock: два правила", function()
    local rules = css.parseStyleBlock(
        "a { color: lightBlue; } .danger { color: red; }"
    )
    assert_eq(#rules, 2)
    assert_eq(rules[1].selectors[1], "a")
    assert_eq(rules[1].declarations.fg, colors.lightBlue)
    assert_eq(rules[2].selectors[1], ".danger")
    assert_eq(rules[2].declarations.fg, colors.red)
end)

test("parseStyleBlock: комментарии убираются", function()
    local rules = css.parseStyleBlock(
        "/* hello */ p { color: red; } /* world */"
    )
    assert_eq(#rules, 1)
    assert_eq(rules[1].declarations.fg, colors.red)
end)

test("parseStyleBlock: группа селекторов через запятую", function()
    local rules = css.parseStyleBlock("h1, h2, h3 { font-weight: bold; }")
    assert_eq(#rules, 1)
    assert_eq(#rules[1].selectors, 3)
    assert_eq(rules[1].selectors[2], "h2")
    assert_eq(rules[1].declarations.bold, true)
end)

test("parseStyleBlock: пустой ввод", function()
    local rules = css.parseStyleBlock("")
    assert_eq(#rules, 0)
end)

test("parseStyleBlock: неизвестные свойства не создают правил", function()
    local rules = css.parseStyleBlock("p { font-size: 14px; margin: 10px; }")
    -- Ни одно свойство не распозналось -> правило пустое и пропущено.
    assert_eq(#rules, 0)
end)

-- -----------------------------------------------------------------------
-- selectorMatch
-- -----------------------------------------------------------------------

local function elem(tag, attrs, children)
    return {
        kind = "elem", tag = tag,
        attrs = attrs or {}, children = children or {},
    }
end

test("selectorMatch: tag", function()
    local n = elem("p")
    assert_true(css.selectorMatch(n, "p"))
    assert_true(not css.selectorMatch(n, "div"))
end)

test("selectorMatch: .class", function()
    local n = elem("p", { class = "hi world" })
    assert_true(css.selectorMatch(n, ".hi"))
    assert_true(css.selectorMatch(n, ".world"))
    assert_true(not css.selectorMatch(n, ".missing"))
end)

test("selectorMatch: #id", function()
    local n = elem("p", { id = "main" })
    assert_true(css.selectorMatch(n, "#main"))
    assert_true(not css.selectorMatch(n, "#other"))
end)

test("selectorMatch: tag.class", function()
    local n = elem("a", { class = "btn primary" })
    assert_true(css.selectorMatch(n, "a.btn"))
    assert_true(css.selectorMatch(n, "a.primary"))
    assert_true(not css.selectorMatch(n, "a.missing"))
    assert_true(not css.selectorMatch(n, "div.btn"))
end)

test("selectorMatch: *", function()
    assert_true(css.selectorMatch(elem("anything"), "*"))
end)

test("selectorMatch: descendant 'div p'", function()
    local body = elem("body")
    local div  = elem("div")
    local p    = elem("p")
    local ancestors = { body, div }
    assert_true(css.selectorMatch(p, "div p", ancestors))
    assert_true(css.selectorMatch(p, "body p", ancestors))
    assert_true(not css.selectorMatch(p, "section p", ancestors))
end)

-- -----------------------------------------------------------------------
-- apply
-- -----------------------------------------------------------------------

test("apply: inline style попадает в node.style", function()
    local root = elem("body", {}, {
        elem("p", { style = "color: red; font-weight: bold" }),
    })
    css.apply(root, {})
    local p = root.children[1]
    assert_eq(p.style.fg, colors.red)
    assert_eq(p.style.bold, true)
end)

test("apply: правила из style-блока применяются", function()
    local root = elem("body", {}, {
        elem("a", { class = "danger" }),
    })
    local rules = css.parseStyleBlock(".danger { color: red; }")
    css.apply(root, rules)
    assert_eq(root.children[1].style.fg, colors.red)
end)

test("apply: inline перекрывает правила", function()
    local root = elem("body", {}, {
        elem("p", { class = "x", style = "color: blue" }),
    })
    local rules = css.parseStyleBlock(".x { color: red; }")
    css.apply(root, rules)
    assert_eq(root.children[1].style.fg, colors.blue)
end)

test("apply: наследование fg от родителя", function()
    local child = elem("span")
    local root = elem("body", { style = "color: red" }, { child })
    css.apply(root, {})
    assert_eq(child.style.fg, colors.red)
end)

test("apply: background не наследуется", function()
    local child = elem("span")
    local root = elem("body", { style = "background-color: yellow" }, { child })
    css.apply(root, {})
    assert_nil(child.style.bg)
end)

-- -----------------------------------------------------------------------
-- Итог
-- -----------------------------------------------------------------------

print(string.format("\n%d run, %d failed", tests_run, tests_fail))
if tests_fail > 0 then
    for _, name in ipairs(failed_names) do print("  - " .. name) end
    os.exit(1)
end
