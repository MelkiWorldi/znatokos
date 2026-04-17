-- Чат через rednet broadcast. Два цикла: приём и отправка.
local net = znatokos.use("net/rednet")

local M = {}

function M.run(nickname)
    if not net.ensureOpen() then
        print("Нет модема. Присоедините модем к компьютеру.")
        return 1
    end
    nickname = nickname or net.label()
    print("Чат ЗнатокOS. Ник: " .. nickname .. ". /quit для выхода.")
    print("Отправитель: компьютер #" .. net.id())
    print(string.rep("-", 30))

    local recvCo = function()
        while true do
            local msg = net.receive("znatokos.chat")
            if msg then
                term.setTextColor(colors.lime)
                io.write("\n<" .. (msg.payload.nick or "?") .. "@" .. msg.from .. "> ")
                term.setTextColor(colors.white)
                io.write(tostring(msg.payload.text) .. "\n> ")
            end
        end
    end

    local sendCo = function()
        while true do
            io.write("> ")
            local line = read()
            if line == "/quit" then return end
            if line and #line > 0 then
                net.broadcast("znatokos.chat", { nick = nickname, text = line })
            end
        end
    end

    parallel.waitForAny(recvCo, sendCo)
    return 0
end

return M
