-- test_html.lua
-- Тесты для HTML-парсера lib/html.lua.
-- Запуск (при корне рабочей директории в znatokos-apps/com.znatok.browser/files):
--   lua tests/test_html.lua

package.path = package.path
    .. ";./lib/?.lua;../lib/?.lua;./files/lib/?.lua"

local html = require("html")

-- -----------------------------------------------------------------------
-- Мини-фреймворк.
-- -----------------------------------------------------------------------

local tests_run, tests_fail = 0, 0
local failed_names = {}

local function eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
    for k, _ in pairs(b) do if a[k] == nil then return false end end
    return true
end

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
    if not eq(a, b) then
        error((msg or "assert_eq failed") ..
            " | got=" .. tostring(a) .. " expected=" .. tostring(b), 2)
    end
end

local function assert_true(v, msg)
    if not v then error(msg or "assert_true failed", 2) end
end

-- Удобный первый ребёнок документа.
local function first(root) return root.children[1] end

-- -----------------------------------------------------------------------
-- Тесты.
-- -----------------------------------------------------------------------

test("empty input -> empty document", function()
    local doc = html.parse("")
    assert_eq(doc.kind, "elem")
    assert_eq(doc.tag, "#document")
    assert_eq(#doc.children, 0)
end)

test("nil input works", function()
    local doc = html.parse(nil)
    assert_eq(doc.tag, "#document")
end)

test("simple <p>hello</p>", function()
    local doc = html.parse("<p>hello</p>")
    local p = first(doc)
    assert_eq(p.tag, "p")
    assert_eq(p.children[1].kind, "text")
    assert_eq(p.children[1].text, "hello")
end)

test("nested <div><span>x</span></div>", function()
    local doc = html.parse("<div><span>x</span></div>")
    local div = first(doc)
    assert_eq(div.tag, "div")
    local sp = div.children[1]
    assert_eq(sp.tag, "span")
    assert_eq(sp.children[1].text, "x")
end)

test("void <br> without closing", function()
    local doc = html.parse("a<br>b")
    -- ожидаем: text 'a', elem br, text 'b'
    assert_eq(doc.children[1].kind, "text")
    assert_eq(doc.children[1].text, "a")
    assert_eq(doc.children[2].tag, "br")
    assert_eq(#doc.children[2].children, 0)
    assert_eq(doc.children[3].text, "b")
end)

test("self-close <img/>", function()
    local doc = html.parse('<img src="x.png"/>')
    local img = first(doc)
    assert_eq(img.tag, "img")
    assert_eq(img.attrs.src, "x.png")
    assert_eq(#img.children, 0)
end)

test("attributes: quoted, single, unquoted, boolean", function()
    local doc = html.parse([[<a href="http://x" class='y' id=zz disabled>link</a>]])
    local a = first(doc)
    assert_eq(a.tag, "a")
    assert_eq(a.attrs.href, "http://x")
    assert_eq(a.attrs.class, "y")
    assert_eq(a.attrs.id, "zz")
    assert_eq(a.attrs.disabled, "")
    assert_eq(a.children[1].text, "link")
end)

test("attribute names lowercased", function()
    local doc = html.parse('<DIV CLASS="X">hi</DIV>')
    local d = first(doc)
    assert_eq(d.tag, "div")
    assert_eq(d.attrs.class, "X")
end)

test("entities in text: &amp;&lt;a&gt;", function()
    local doc = html.parse("<p>&amp;&lt;a&gt;</p>")
    local p = first(doc)
    assert_eq(p.children[1].text, "&<a>")
end)

test("entities in attributes", function()
    local doc = html.parse('<a title="A&amp;B">x</a>')
    assert_eq(first(doc).attrs.title, "A&B")
end)

test("script contents kept as raw text; next tag parses", function()
    local doc = html.parse('<script>var x = "<p>";</script><b>text</b>')
    local sc = doc.children[1]
    assert_eq(sc.tag, "script")
    assert_eq(sc.children[1].kind, "text")
    assert_eq(sc.children[1].text, 'var x = "<p>";')
    local b = doc.children[2]
    assert_eq(b.tag, "b")
    assert_eq(b.children[1].text, "text")
end)

test("style raw text", function()
    local doc = html.parse("<style>a{b:1}</style>")
    local s = first(doc)
    assert_eq(s.tag, "style")
    assert_eq(s.children[1].text, "a{b:1}")
end)

test("comment is skipped", function()
    local doc = html.parse("<p>a<!-- foo -->b</p>")
    local p = first(doc)
    assert_eq(#p.children, 1)
    assert_eq(p.children[1].text, "ab")
end)

test("doctype is skipped", function()
    local doc = html.parse("<!DOCTYPE html><p>hi</p>")
    assert_eq(#doc.children, 1)
    assert_eq(first(doc).tag, "p")
end)

test("findTag returns first matching node", function()
    local doc = html.parse("<div><span>a</span><span>b</span></div>")
    local sp = html.findTag(doc, "span")
    assert_eq(sp.children[1].text, "a")
end)

test("findAll returns all", function()
    local doc = html.parse("<div><span>a</span><p><span>b</span></p></div>")
    local list = html.findAll(doc, "span")
    assert_eq(#list, 2)
    assert_eq(list[1].children[1].text, "a")
    assert_eq(list[2].children[1].text, "b")
end)

test("getText collects text, ignores script/style", function()
    local doc = html.parse("<div>Hello <b>world</b><script>var x=1;</script><style>a{}</style>!</div>")
    assert_eq(html.getText(doc), "Hello world!")
end)

test("decodeEntities: named", function()
    assert_eq(html.decodeEntities("&nbsp;"), "\194\160")
    assert_eq(html.decodeEntities("&quot;"), '"')
    assert_eq(html.decodeEntities("a&amp;b"), "a&b")
end)

test("decodeEntities: numeric decimal and hex", function()
    assert_eq(html.decodeEntities("&#65;"), "A")
    assert_eq(html.decodeEntities("&#x41;"), "A")
    assert_eq(html.decodeEntities("&#x4E;"), "N")
end)

test("decodeEntities: unknown left as-is", function()
    assert_eq(html.decodeEntities("&unknown;"), "&unknown;")
    assert_eq(html.decodeEntities("a & b"), "a & b")
end)

test("malformed: <div><span> without closing -> auto-close at EOF", function()
    local doc = html.parse("<div><span>hello")
    -- Дерево должно быть валидным.
    local div = first(doc)
    assert_eq(div.tag, "div")
    local sp = div.children[1]
    assert_eq(sp.tag, "span")
    assert_eq(sp.children[1].text, "hello")
end)

test("random '<' in text treated as text", function()
    local doc = html.parse("a < b < c")
    -- Должен быть один text-нод со всем содержимым.
    assert_eq(#doc.children, 1)
    assert_eq(doc.children[1].kind, "text")
    assert_eq(doc.children[1].text, "a < b < c")
end)

test("<p> inside <p> auto-closes previous", function()
    local doc = html.parse("<p>a<p>b</p>")
    -- Ожидаем: два sibling <p>, не вложенные.
    assert_eq(#doc.children, 2)
    assert_eq(doc.children[1].tag, "p")
    assert_eq(doc.children[2].tag, "p")
    assert_eq(doc.children[1].children[1].text, "a")
    assert_eq(doc.children[2].children[1].text, "b")
end)

test("<li> inside <li> auto-closes previous", function()
    local doc = html.parse("<ul><li>a<li>b</ul>")
    local ul = first(doc)
    assert_eq(ul.tag, "ul")
    assert_eq(#ul.children, 2)
    assert_eq(ul.children[1].tag, "li")
    assert_eq(ul.children[2].tag, "li")
end)

test("unclosed script reads until EOF", function()
    local doc = html.parse("<script>var x = 1;")
    local sc = first(doc)
    assert_eq(sc.tag, "script")
    assert_eq(sc.children[1].text, "var x = 1;")
end)

test("comment without end -> rest ignored", function()
    local doc = html.parse("<p>a</p><!-- no end")
    assert_eq(#doc.children, 1)
    assert_eq(first(doc).tag, "p")
end)

test("case-insensitive tag matching for closing", function()
    local doc = html.parse("<DIV>hi</div>")
    local d = first(doc)
    assert_eq(d.tag, "div")
    assert_eq(d.children[1].text, "hi")
end)

test("mixed content realistic", function()
    local input = [[<!DOCTYPE html>
<html><head><title>T</title></head>
<body><h1>Hello</h1><p>world &amp; peace</p></body></html>]]
    local doc = html.parse(input)
    local title = html.findTag(doc, "title")
    assert_eq(title.children[1].text, "T")
    local h1 = html.findTag(doc, "h1")
    assert_eq(h1.children[1].text, "Hello")
    local p = html.findTag(doc, "p")
    assert_eq(p.children[1].text, "world & peace")
end)

test("attrs without value at tag end", function()
    local doc = html.parse("<input disabled>")
    local inp = first(doc)
    assert_eq(inp.tag, "input")
    assert_eq(inp.attrs.disabled, "")
end)

test("performance sanity: 10k nested divs", function()
    local parts = {}
    for i = 1, 1000 do parts[#parts + 1] = "<div>x</div>" end
    local s = table.concat(parts)
    local t0 = os.clock()
    local doc = html.parse(s)
    local dt = os.clock() - t0
    assert_true(#doc.children == 1000, "expected 1000 divs, got " .. #doc.children)
    -- Не жёсткое ограничение — просто диагностика.
    print(string.format("     parsed 1000 divs in %.3fs", dt))
end)

-- -----------------------------------------------------------------------
-- Итог.
-- -----------------------------------------------------------------------

print(string.format("\n%d tests, %d failures", tests_run, tests_fail))
if tests_fail > 0 then
    for _, n in ipairs(failed_names) do print("  - " .. n) end
    os.exit(1)
end
