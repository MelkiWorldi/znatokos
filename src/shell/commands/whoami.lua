local vfs = znatokos.use("fs/vfs")
return function()
    local u = vfs.getUser()
    print(("%s  uid=%d  gid=%d"):format(u.user, u.uid, u.gid))
    return 0
end
