import alloc.string.{ String, new }

const K: [u32; 64] = [
    0x428a2f98u32, 0x71374491u32, 0xb5c0fbcfu32, 0xe9b5dba5u32, 0x3956c25bu32, 0x59f111f1u32, 0x923f82a4u32, 0xab1c5ed5u32,
    0xd807aa98u32, 0x12835b01u32, 0x243185beu32, 0x550c7dc3u32, 0x72be5d74u32, 0x80deb1feu32, 0x9bdc06a7u32, 0xc19bf174u32,
    0xe49b69c1u32, 0xefbe4786u32, 0x0fc19dc6u32, 0x240ca1ccu32, 0x2de92c6fu32, 0x4a7484aau32, 0x5cb0a9dcu32, 0x76f988dau32,
    0x983e5152u32, 0xa831c66du32, 0xb00327c8u32, 0xbf597fc7u32, 0xc6e00bf3u32, 0xd5a79147u32, 0x06ca6351u32, 0x14292967u32,
    0x27b70a85u32, 0x2e1b2138u32, 0x4d2c6dfcu32, 0x53380d13u32, 0x650a7354u32, 0x766a0abbu32, 0x81c2c92eu32, 0x92722c85u32,
    0xa2bfe8a1u32, 0xa81a664bu32, 0xc24b8b70u32, 0xc76c51a3u32, 0xd192e819u32, 0xd6990624u32, 0xf40e3585u32, 0x106aa070u32,
    0x19a4c116u32, 0x1e376c08u32, 0x2748774cu32, 0x34b0bcb5u32, 0x391c0cb3u32, 0x4ed8aa4au32, 0x5b9cca4fu32, 0x682e6ff3u32,
    0x748f82eeu32, 0x78a5636fu32, 0x84c87814u32, 0x8cc70208u32, 0x90befffau32, 0xa4506cebu32, 0xbef9a3f7u32, 0xc67178f2u32
]

pub type Sha256 { state: [u32; 8]; block: [u8; 64]; used: usize; bytes: u64 }

extend Sha256 {
    pub init() {
        self.state = [0x6a09e667u32, 0xbb67ae85u32, 0x3c6ef372u32, 0xa54ff53au32,
            0x510e527fu32, 0x9b05688cu32, 0x1f83d9abu32, 0x5be0cd19u32]
        self.block = [0u8; 64]
        self.used = 0usize
        self.bytes = 0u64
    }

    pub mut fn update(read input: [u8]): Unit {
        self.bytes = self.bytes.wrapping_add(input.len() as u64)
        var offset = 0usize
        while offset < input.len() {
            if self.used == 0 && input.len() - offset >= 64 {
                compress(mut self.state, input[offset..offset + 64])
                offset += 64
                continue
            }
            let count = (64usize - self.used).min(input.len() - offset)
            let end = self.used + count
            var destination = mut self.block[self.used..end]
            destination.copy_from_slice(input[offset..offset + count])
            self.used = end
            offset += count
            if self.used == 64 {
                compress(mut self.state, self.block)
                self.used = 0
            }
        }
    }

    pub mut fn finish(): String {
        let length = self.bytes.wrapping_mul(8u64).to_be_bytes()
        var padding = [0u8; 64]
        padding[0] = 128u8
        let count = if self.used < 56 { 56usize - self.used } else { 120usize - self.used }
        self.update(padding[..count])
        self.update(length)
        var out = new()
        for word in self.state {
            var shift = 32u32
            while shift != 0 {
                shift -= 4
                out.push(hex_digit((word >> shift) & 15u32))
            }
        }
        out
    }
}

pub fn hex_digit(nibble: u32): char {
    let digits = "0123456789abcdef"
    core.char.from_u32(digits.as_bytes()[nibble as usize] as u32).or_panic()
}

fn compress(mut state: [u32; 8], read block: [u8]): Unit {
    var words = [0u32; 64]
    var i = 0usize
    while i < 16 {
        let offset = i * 4
        words[i] = (block[offset] as u32 << 24) | (block[offset + 1] as u32 << 16) |
            (block[offset + 2] as u32 << 8) | block[offset + 3] as u32
        i += 1
    }
    while i < 64 {
        let x = words[i - 15]
        let y = words[i - 2]
        let s0 = x.rotate_right(7u32) ^ x.rotate_right(18u32) ^ (x >> 3)
        let s1 = y.rotate_right(17u32) ^ y.rotate_right(19u32) ^ (y >> 10)
        words[i] = words[i - 16].wrapping_add(s0).wrapping_add(words[i - 7]).wrapping_add(s1)
        i += 1
    }
    var a = state[0]
    var b = state[1]
    var c = state[2]
    var d = state[3]
    var e = state[4]
    var f = state[5]
    var g = state[6]
    var h = state[7]
    i = 0
    while i < 64 {
        let sum1 = e.rotate_right(6u32) ^ e.rotate_right(11u32) ^ e.rotate_right(25u32)
        let choose = (e & f) ^ ((e ^ 0xffffffffu32) & g)
        let t1 = h.wrapping_add(sum1).wrapping_add(choose).wrapping_add(K[i]).wrapping_add(words[i])
        let sum0 = a.rotate_right(2u32) ^ a.rotate_right(13u32) ^ a.rotate_right(22u32)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let t2 = sum0.wrapping_add(majority)
        h = g
        g = f
        f = e
        e = d.wrapping_add(t1)
        d = c
        c = b
        b = a
        a = t1.wrapping_add(t2)
        i += 1
    }
    let result = [a, b, c, d, e, f, g, h]
    i = 0
    while i < 8 {
        state[i] = state[i].wrapping_add(result[i])
        i += 1
    }
}
