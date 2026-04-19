-- src/audio/speaker.lua — высокоуровневое API звука для ZnatokOS.
-- Обёртка над CC:Tweaked speaker peripheral.
--
-- Методы ищут все подключённые speakers (wired-modem сетка тоже работает)
-- и отправляют команду на первый доступный. Для многоканального использования
-- напрямую работай через peripheral.wrap(...).
--
-- Экспорты:
--   M.list()               — список имён speaker'ов
--   M.hasAny()             — bool
--   M.playNote(instr, vol, pitch)   — note-block звук
--   M.playSound(name, vol, pitch)   — MC sound event ("block.note_block.bell")
--   M.playAudio(buffer)    — DFPWM (таблица int8 samples); возвращает ok
--   M.playTune(notes)      — последовательность нот {{instr, pitch, duration_sec}}
--   M.stop()               — остановить всё на первом speaker'е
--   M.stopAll()            — остановить на ВСЕХ speakers

local M = {}

local function findAll()
    local out = {}
    if not peripheral then return out end
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "speaker" then
            out[#out + 1] = peripheral.wrap(side)
        end
    end
    return out
end

function M.list()
    local names = {}
    if not peripheral then return names end
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "speaker" then
            names[#names + 1] = side
        end
    end
    return names
end

function M.hasAny()
    return #M.list() > 0
end

-- Воспроизвести "ноту" через note-block. instrument: harp/basedrum/snare/...
-- pitch: 0..24 (2 октавы), vol: 0..3.
function M.playNote(instrument, volume, pitch)
    local all = findAll()
    if #all == 0 then return false, "нет speaker" end
    return all[1].playNote(instrument or "harp", volume or 1, pitch or 12)
end

-- Любой MC sound event. Вернёт false если ресурс не найден.
function M.playSound(name, volume, pitch)
    local all = findAll()
    if #all == 0 then return false, "нет speaker" end
    return all[1].playSound(name, volume or 1, pitch or 1)
end

-- DFPWM аудио буфер (array of signed bytes, -128..127).
-- Возвращает true если буфер принят; false если speaker занят.
function M.playAudio(buffer, volume)
    local all = findAll()
    if #all == 0 then return false, "нет speaker" end
    return all[1].playAudio(buffer, volume)
end

-- Простая мелодия: массив {instrument, pitch, duration_sec}.
-- Блокирует до окончания (через sleep). Для фоновой — оберни в parallel/spawn.
function M.playTune(notes)
    local all = findAll()
    if #all == 0 then return false, "нет speaker" end
    local sp = all[1]
    for _, n in ipairs(notes) do
        sp.playNote(n[1] or "harp", n[2] or 1, n[3] or 12)
        if n[4] and n[4] > 0 then sleep(n[4]) end
    end
    return true
end

function M.stop()
    local all = findAll()
    if #all == 0 then return end
    if all[1].stop then pcall(all[1].stop) end
end

function M.stopAll()
    for _, sp in ipairs(findAll()) do
        if sp.stop then pcall(sp.stop) end
    end
end

-- Стриминг DFPWM из памяти. Декодер берёт 16 байт за раз и шлёт как audio-chunks.
-- buffer — бинарная строка из http.get (DFPWM raw).
-- Требует наличия cc.audio.dfpwm в окружении (доступен в CC:Tweaked с 1.100).
function M.streamDFPWM(rawBytes, volume)
    local ok, dfpwm = pcall(require, "cc.audio.dfpwm")
    if not ok or not dfpwm then return false, "cc.audio.dfpwm недоступен" end
    local all = findAll()
    if #all == 0 then return false, "нет speaker" end
    local sp = all[1]
    local decoder = dfpwm.make_decoder()
    -- DFPWM бёт 6000 samples/sec. Чанк 16*1024 байт = 16384 samples ~2.7 сек.
    local CHUNK = 16 * 1024
    for i = 1, #rawBytes, CHUNK do
        local chunk = rawBytes:sub(i, i + CHUNK - 1)
        local decoded = decoder(chunk)
        while not sp.playAudio(decoded, volume) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    return true
end

return M
