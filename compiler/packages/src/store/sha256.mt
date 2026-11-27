import alloc.string.{ String, with_capacity }

const ROUND: [u32; 64] = [
    0x428a2f98u32, 0x71374491u32, 0xb5c0fbcfu32, 0xe9b5dba5u32, 0x3956c25bu32, 0x59f111f1u32,
    0x923f82a4u32, 0xab1c5ed5u32,
    0xd807aa98u32, 0x12835b01u32, 0x243185beu32, 0x550c7dc3u32, 0x72be5d74u32, 0x80deb1feu32,
    0x9bdc06a7u32, 0xc19bf174u32,
    0xe49b69c1u32, 0xefbe4786u32, 0x0fc19dc6u32, 0x240ca1ccu32, 0x2de92c6fu32, 0x4a7484aau32,
    0x5cb0a9dcu32, 0x76f988dau32,
    0x983e5152u32, 0xa831c66du32, 0xb00327c8u32, 0xbf597fc7u32, 0xc6e00bf3u32, 0xd5a79147u32,
    0x06ca6351u32, 0x14292967u32,
    0x27b70a85u32, 0x2e1b2138u32, 0x4d2c6dfcu32, 0x53380d13u32, 0x650a7354u32, 0x766a0abbu32,
    0x81c2c92eu32, 0x92722c85u32,
    0xa2bfe8a1u32, 0xa81a664bu32, 0xc24b8b70u32, 0xc76c51a3u32, 0xd192e819u32, 0xd6990624u32,
    0xf40e3585u32, 0x106aa070u32,
    0x19a4c116u32, 0x1e376c08u32, 0x2748774cu32, 0x34b0bcb5u32, 0x391c0cb3u32, 0x4ed8aa4au32,
    0x5b9cca4fu32, 0x682e6ff3u32,
    0x748f82eeu32, 0x78a5636fu32, 0x84c87814u32, 0x8cc70208u32, 0x90befffau32, 0xa4506cebu32,
    0xbef9a3f7u32, 0xc67178f2u32
]

fn compress(mut state: [u32; 8], read block: [u8]): Unit {
    var words = [0u32; 64]
    for i in 0usize..16usize {
        let p = i * 4usize
        words[i] = (block[p] as u32 << 24u32) | (block[p + 1usize] as u32 << 16u32) |
            (block[p + 2usize] as u32 << 8u32) | block[p + 3usize] as u32
    }
    for i in 16usize..64usize {
        let x = words[i - 15usize]
        let y = words[i - 2usize]
        let s0 = x.rotate_right(7u32) ^ x.rotate_right(18u32) ^ (x >> 3u32)
        let s1 = y.rotate_right(17u32) ^ y.rotate_right(19u32) ^ (y >> 10u32)
        words[i] = words[i - 16usize].wrapping_add(s0).wrapping_add(words[i -
            7usize]).wrapping_add(s1)
    }
    var a = state[0]
    var b = state[1]
    var c = state[2]
    var d = state[3]
    var e = state[4]
    var f = state[5]
    var g = state[6]
    var h = state[7]
    for i in 0usize..64usize {
        let s1 = e.rotate_right(6u32) ^ e.rotate_right(11u32) ^ e.rotate_right(25u32)
        let choose = g ^ (e & (f ^ g))
        let t1 = h.wrapping_add(s1).wrapping_add(choose).wrapping_add(ROUND[i]).wrapping_add(words[i])
        let s0 = a.rotate_right(2u32) ^ a.rotate_right(13u32) ^ a.rotate_right(22u32)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        h = g
        g = f
        f = e
        e = d.wrapping_add(t1)
        d = c
        c = b
        b = a
        a = t1.wrapping_add(s0).wrapping_add(majority)
    }
    let round = [a, b, c, d, e, f, g, h]
    for i in 0usize..8usize { state[i] = state[i].wrapping_add(round[i]) }
}

pub fn hex(read bytes: [u8]): String {
    var state = [0x6a09e667u32, 0xbb67ae85u32, 0x3c6ef372u32, 0xa54ff53au32,
        0x510e527fu32, 0x9b05688cu32, 0x1f83d9abu32, 0x5be0cd19u32]
    var offset = 0usize
    while bytes.len() - offset >= 64usize {
        compress(mut state, read bytes[offset..offset + 64usize])
        offset += 64usize
    }
    let rest = bytes.len() - offset
    var tail = [0u8; 64]
    tail.split_at_mut(rest).0.copy_from_slice(read bytes[offset..])
    tail[rest] = 128u8
    if rest >= 56usize {
        compress(mut state, tail)
        tail = [0u8; 64]
    }
    let bits = (bytes.len() as u64).wrapping_mul(8u64)
    for i in 0usize..8usize { tail[63usize - i] = (bits >> (i as u64 * 8u64)) as u8 }
    compress(mut state, tail)

    let digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']
    var result = with_capacity(64usize)
    for i in 0usize..8usize {
        for nibble in 0u32..8u32 {
            let index = (state[i] >> ((7u32 - nibble) * 4u32)) & 15u32
            result.push(digits[index as usize])
        }
    }
    result
}

@test
fn known_sha256_vectors(): Unit {
    let empty = hex("".as_bytes())
    assert(empty.as_text() == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "wrong empty digest")
    let two_padding_blocks = hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".as_bytes())
    assert(two_padding_blocks.as_text() ==
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "wrong 56-byte digest")
    let aligned = hex([0u8; 64])
    assert(aligned.as_text() == "f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b",
        "wrong 64-byte digest")
}
