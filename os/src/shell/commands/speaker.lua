-- speaker: управление и тест колонок.
-- Использование:
--   speaker list                 — показать подключённые speaker'ы
--   speaker note [instr] [pitch] — проиграть ноту (default: harp, 12)
--   speaker sound <name>         — проиграть MC-событие (block.note_block.bell)
--   speaker tune <name>          — встроенная мелодия: intro|beep|error|fanfare
--   speaker stop                 — остановить всё
local audio = znatokos.use("audio/speaker")

local TUNES = {
    intro   = {{"harp",1,6,0.15},{"harp",1,12,0.15},{"harp",1,18,0.3}},
    beep    = {{"pling",2,14,0.1}},
    error   = {{"basedrum",2,4,0.15},{"basedrum",2,2,0.25}},
    fanfare = {{"bell",2,12,0.2},{"bell",2,14,0.2},{"bell",2,16,0.2},{"bell",2,19,0.5}},
    arcade  = {{"bit",2,12,0.1},{"bit",2,16,0.1},{"bit",2,19,0.1},{"bit",2,24,0.2}},
}

return function(args)
    local sub = args[2] or "list"

    if sub == "list" then
        local speakers = audio.list()
        if #speakers == 0 then
            print("Колонок не найдено.")
            print("Присоедините speaker к компьютеру (любая сторона или через wired-модем).")
            return 1
        end
        print("Найдено " .. #speakers .. " колонок:")
        for i, s in ipairs(speakers) do print(("  %d. %s"):format(i, s)) end
        return 0

    elseif sub == "note" then
        local instr = args[3] or "harp"
        local pitch = tonumber(args[4]) or 12
        local ok, err = audio.playNote(instr, 1, pitch)
        if not ok then print("Ошибка: " .. tostring(err)); return 1 end
        print(("Нота: %s, pitch=%d"):format(instr, pitch))
        return 0

    elseif sub == "sound" then
        local name = args[3]
        if not name then print("Использование: speaker sound <event>"); return 1 end
        local ok, err = audio.playSound(name, tonumber(args[4]) or 1, tonumber(args[5]) or 1)
        if not ok then print("Ошибка: " .. tostring(err)); return 1 end
        print("Звук: " .. name)
        return 0

    elseif sub == "tune" then
        local name = args[3] or "intro"
        local t = TUNES[name]
        if not t then
            print("Нет мелодии '" .. name .. "'. Доступны:")
            for k, _ in pairs(TUNES) do print("  " .. k) end
            return 1
        end
        print("Играю: " .. name)
        audio.playTune(t)
        return 0

    elseif sub == "stop" then
        audio.stopAll()
        print("Остановлено.")
        return 0

    else
        print("speaker list|note|sound|tune|stop")
        return 1
    end
end
