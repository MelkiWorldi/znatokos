local layout = znatokos.use("ui/layout")
local T = _G._T

-- row с фикс размерами
local r = layout.row({ x=1, y=1, w=20, h=1, gap=1,
    children = { { w=5 }, { w=5 }, { w=5 } } })
T.assertEq(r[1].x, 1, "row 1.x")
T.assertEq(r[2].x, 7, "row 2.x")  -- 1 + 5 + 1 gap
T.assertEq(r[3].x, 13, "row 3.x")
T.assertEq(r[1].w, 5, "row 1.w")

-- row с flex
local r2 = layout.row({ x=1, y=1, w=20, h=1, gap=0,
    children = { { w=5 }, { flex=1 }, { flex=2 } } })
T.assertEq(r2[1].w, 5, "fixed kept")
T.assertEq(r2[2].w + r2[3].w, 15, "flex total")
T.assertTrue(r2[3].w >= r2[2].w, "flex 2 larger than flex 1")

-- column
local c = layout.column({ x=1, y=1, w=10, h=10, gap=0,
    children = { { h=3 }, { h=3 }, { h=4 } } })
T.assertEq(c[1].y, 1, "col y1")
T.assertEq(c[2].y, 4, "col y2")
T.assertEq(c[3].y, 7, "col y3")

-- grid
local g = layout.grid({ x=1, y=1, w=10, h=10, cols=2, rows=2,
    children = {{}, {}, {}, {}} })
T.assertEq(g[1].x, 1, "grid 11")
T.assertEq(g[2].x, 6, "grid 12")
T.assertEq(g[3].y, 6, "grid 21")

-- center
local cx, cy, cw, ch = layout.center(1, 1, 20, 10, 8, 4)
T.assertEq(cw, 8, "center w"); T.assertEq(ch, 4, "center h")
T.assertEq(cx, 7, "center x"); T.assertEq(cy, 4, "center y")
