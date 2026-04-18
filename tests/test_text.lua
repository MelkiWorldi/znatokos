-- Тесты util/text
local text = znatokos.use("util/text")
local T = _G._T

T.assertEq(text.len(""), 0, "empty len")
T.assertEq(text.len("abc"), 3, "ascii len")
T.assertEq(text.len("Привет"), 6, "cyrillic len")
T.assertEq(text.len("Ёё"), 2, "ё len")

T.assertEq(text.sub("abcdef", 2, 4), "bcd", "ascii sub")
T.assertEq(text.sub("Привет", 1, 3), "При", "cyrillic sub")
T.assertEq(text.sub("Привет", 4, 6), "вет", "cyrillic sub end")

local wr = text.wrap("один два три четыре пять шесть", 10)
T.assertTrue(#wr >= 2, "wrap produces multiple lines")
for _, line in ipairs(wr) do
    T.assertTrue(text.len(line) <= 10, "wrap line within width: " .. line)
end

T.assertEq(text.ellipsize("длинная строка", 8), "длинная…", "ellipsize cyrillic")
T.assertEq(text.pad("ab", 5), "ab   ", "pad left")
T.assertEq(text.pad("ab", 5, "right"), "   ab", "pad right")
T.assertEq(text.center("X", 5), "  X  ", "center")
