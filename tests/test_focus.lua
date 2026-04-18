local focus = znatokos.use("ui/focus")
local T = _G._T

local a = { x=1, y=1, w=5, h=1 }
local b = { x=10, y=1, w=5, h=1 }
local c = { x=1, y=5, w=5, h=1 }
local d = { x=10, y=5, w=5, h=1 }
local items = { a, b, c, d }

T.assertEq(focus.next(items, a), b, "next a→b")
T.assertEq(focus.next(items, d), a, "next d→a (wrap)")
T.assertEq(focus.prev(items, a), d, "prev a→d (wrap)")

T.assertEq(focus.move(items, a, "right"), b, "right a→b")
T.assertEq(focus.move(items, a, "down"), c, "down a→c")
T.assertEq(focus.move(items, b, "left"), a, "left b→a")
T.assertEq(focus.move(items, d, "up"), b, "up d→b")
