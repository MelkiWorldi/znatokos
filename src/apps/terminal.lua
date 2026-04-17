-- Приложение "Терминал": запускает шелл в текущем окне.
local shell_mod = znatokos.use("shell/shell")
return function(user)
    shell_mod.run({ cwd = user and user.home or "/home" })
end
