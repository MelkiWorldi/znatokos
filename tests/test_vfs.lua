-- Проверка VFS: запись, чтение, проверка прав.
local vfs = znatokos.use("fs/vfs")
local T = _G._T

local TMP = "/znatokos/var/tmp/vfs_test"
pcall(vfs.delete, TMP)

-- root может писать в /znatokos
vfs.setUser({ user = "root", uid = 0, gid = 0 })
vfs.write(TMP, "hello")
T.assertEq(vfs.read(TMP), "hello", "root can write/read")

-- обычный пользователь не может писать в системный путь без ACL
vfs.setUser({ user = "alice", uid = 1000, gid = 1000 })
local ok = pcall(vfs.write, "/znatokos/etc/denied.txt", "nope")
T.assertEq(ok, false, "non-root blocked from /znatokos writes")

-- но может писать в /home
local ok2 = pcall(vfs.write, "/home/alice_test.txt", "hi")
T.assertEq(ok2, true, "user can write /home")

-- Восстанавливаем root для остальных тестов
vfs.setUser({ user = "root", uid = 0, gid = 0 })
pcall(vfs.delete, TMP)
pcall(vfs.delete, "/home/alice_test.txt")
