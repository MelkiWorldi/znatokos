local chat = znatokos.use("net/chat")
local vfs  = znatokos.use("fs/vfs")
return function(args)
    local nick = args[2] or vfs.getUser().user
    return chat.run(nick)
end
