-- Проверяем SHA-256 на известных векторах.
local sha = znatokos.use("auth/sha256")
local T = _G._T

T.assertEq(sha.hash(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "sha256('')")
T.assertEq(sha.hash("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    "sha256('abc')")
T.assertEq(sha.hash("The quick brown fox jumps over the lazy dog"),
    "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
    "sha256('quick fox')")

-- saltedHash детерминирован при одинаковой соли
local s = "salt123"
T.assertEq(sha.saltedHash("pw", s), sha.saltedHash("pw", s), "salted deterministic")

-- makeSalt возвращает непустую строку
T.assertTrue(#sha.makeSalt() == 16, "makeSalt length")
