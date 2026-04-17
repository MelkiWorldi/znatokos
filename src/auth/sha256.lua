-- SHA-256 на чистом Lua (работает в CC: Tweaked, использует bit32).
-- Основано на классической компактной реализации. Возвращает hex-строку.
-- В длинных операциях делает sleep(0) чтобы не словить yield-timeout.

local bit = bit32 or bit

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function rrotate(x, n) return bit.bor(bit.rshift(x, n), bit.lshift(x, 32 - n)) end

local function preprocess(msg)
    local len = #msg
    local extra = 64 - ((len + 9) % 64)
    if extra == 64 then extra = 0 end
    msg = msg .. "\128" .. string.rep("\0", extra)
    local bitlen = len * 8
    -- 64-битная длина, big-endian
    msg = msg .. "\0\0\0\0"
    msg = msg .. string.char(bit.band(bit.rshift(bitlen, 24), 0xFF))
    msg = msg .. string.char(bit.band(bit.rshift(bitlen, 16), 0xFF))
    msg = msg .. string.char(bit.band(bit.rshift(bitlen, 8),  0xFF))
    msg = msg .. string.char(bit.band(bitlen, 0xFF))
    return msg
end

local function chunkToW(msg, offset)
    local w = {}
    for i = 0, 15 do
        local p = offset + i * 4
        w[i + 1] = bit.bor(
            bit.lshift(msg:byte(p + 1), 24),
            bit.lshift(msg:byte(p + 2), 16),
            bit.lshift(msg:byte(p + 3), 8),
            msg:byte(p + 4)
        )
    end
    return w
end

local function compress(h, w)
    for i = 17, 64 do
        local s0 = bit.bxor(rrotate(w[i - 15], 7), rrotate(w[i - 15], 18), bit.rshift(w[i - 15], 3))
        local s1 = bit.bxor(rrotate(w[i - 2], 17), rrotate(w[i - 2], 19), bit.rshift(w[i - 2], 10))
        w[i] = bit.band(w[i - 16] + s0 + w[i - 7] + s1, 0xFFFFFFFF)
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 1, 64 do
        local S1 = bit.bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
        local ch = bit.bxor(bit.band(e, f), bit.band(bit.bnot(e), g))
        local t1 = bit.band(hh + S1 + ch + K[i] + w[i], 0xFFFFFFFF)
        local S0 = bit.bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
        local mj = bit.bxor(bit.band(a, b), bit.band(a, c), bit.band(b, c))
        local t2 = bit.band(S0 + mj, 0xFFFFFFFF)
        hh = g; g = f; f = e
        e = bit.band(d + t1, 0xFFFFFFFF)
        d = c; c = b; b = a
        a = bit.band(t1 + t2, 0xFFFFFFFF)
    end
    h[1] = bit.band(h[1] + a, 0xFFFFFFFF)
    h[2] = bit.band(h[2] + b, 0xFFFFFFFF)
    h[3] = bit.band(h[3] + c, 0xFFFFFFFF)
    h[4] = bit.band(h[4] + d, 0xFFFFFFFF)
    h[5] = bit.band(h[5] + e, 0xFFFFFFFF)
    h[6] = bit.band(h[6] + f, 0xFFFFFFFF)
    h[7] = bit.band(h[7] + g, 0xFFFFFFFF)
    h[8] = bit.band(h[8] + hh, 0xFFFFFFFF)
end

local function sha256(msg)
    local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    msg = preprocess(msg)
    local chunks = #msg / 64
    for i = 0, chunks - 1 do
        compress(h, chunkToW(msg, i * 64))
        if i % 4 == 0 and os.queueEvent then
            -- отдаём управление, чтобы CC не убил корутину
            os.queueEvent("znatokos:sha_yield")
            os.pullEvent("znatokos:sha_yield")
        end
    end
    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x",
        h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8])
end

local M = {}
function M.hash(msg) return sha256(msg) end

function M.saltedHash(password, salt)
    return sha256((salt or "") .. "$" .. password)
end

function M.makeSalt()
    local s = ""
    for _ = 1, 16 do s = s .. string.char(math.random(33, 126)) end
    return s
end

return M
