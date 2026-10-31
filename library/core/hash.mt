// Hashing. `Hash` feeds a value's identity into a `Hasher`; values that are
// equal under `Eq` must feed identical bytes, so every implementation below
// hashes exactly what its `PartialEq` compares. Integers are written as
// little-endian bytes, so results do not depend on the host byte order.
import super.cmp.Ordering
import super.text.Text

pub interface Hasher {
    mut fn write(bytes: read [u8]): Unit;
    fn finish(): u64;

    mut fn write_u8(value: u8): Unit {
        let bytes = [value]
        self.write(read bytes)
    }
    mut fn write_u16(value: u16): Unit {
        let bytes = [value as u8, (value >> 8u16) as u8]
        self.write(read bytes)
    }
    mut fn write_u32(value: u32): Unit {
        let bytes = [value as u8, (value >> 8u32) as u8, (value >> 16u32) as u8, (value >> 24u32) as u8]
        self.write(read bytes)
    }
    mut fn write_u64(value: u64): Unit {
        let bytes = [
            value as u8, (value >> 8u64) as u8, (value >> 16u64) as u8, (value >> 24u64) as u8,
            (value >> 32u64) as u8, (value >> 40u64) as u8, (value >> 48u64) as u8, (value >> 56u64) as u8
        ]
        self.write(read bytes)
    }
    mut fn write_u128(value: u128): Unit {
        self.write_u64(value as u64)
        self.write_u64((value >> 64u128) as u64)
    }
    // Widened so the stream does not depend on the pointer width.
    mut fn write_usize(value: usize): Unit { self.write_u64(value as u64) }
}

pub interface Hash {
    fn hash<H: Hasher>(state: mut H): Unit;
}

// Hashes one value with the default keyed SipHash-1-3 (zero key).
pub fn hash_one<T: Hash + unsized>(value: read T): u64 {
    var hasher = sip13(0u64, 0u64)
    value.hash(mut hasher)
    hasher.finish()
}

// FNV-1a, 64 bit: tiny and unkeyed (not collision-attack resistant).
pub type Fnv1a { state: u64 }
pub fn fnv1a(): Fnv1a { Fnv1a(0xcbf29ce484222325u64) }
extend Fnv1a implements Hasher {
    mut fn write(bytes: read [u8]): Unit {
        var i = 0usize
        while i < bytes.len() {
            self.state = (self.state ^ (bytes[i] as u64)).wrapping_mul(0x100000001b3u64)
            i += 1usize
        }
    }
    fn finish(): u64 { self.state }
}

// SipHash with `compression` rounds per 8-byte word and `finalization` rounds at the end.
pub type SipHasher {
    v0: u64; v1: u64; v2: u64; v3: u64
    tail: u64; tail_length: usize; length: usize
    compression: u32; finalization: u32
}
fn sip_round(hasher: mut SipHasher): Unit {
    hasher.v0 = hasher.v0.wrapping_add(hasher.v1)
    hasher.v1 = hasher.v1.rotate_left(13u32) ^ hasher.v0
    hasher.v0 = hasher.v0.rotate_left(32u32)
    hasher.v2 = hasher.v2.wrapping_add(hasher.v3)
    hasher.v3 = hasher.v3.rotate_left(16u32) ^ hasher.v2
    hasher.v0 = hasher.v0.wrapping_add(hasher.v3)
    hasher.v3 = hasher.v3.rotate_left(21u32) ^ hasher.v0
    hasher.v2 = hasher.v2.wrapping_add(hasher.v1)
    hasher.v1 = hasher.v1.rotate_left(17u32) ^ hasher.v2
    hasher.v2 = hasher.v2.rotate_left(32u32)
}
pub fn sip_with_rounds(k0: u64, k1: u64, compression: u32, finalization: u32): SipHasher {
    SipHasher(
        k0 ^ 0x736f6d6570736575u64, k1 ^ 0x646f72616e646f6du64,
        k0 ^ 0x6c7967656e657261u64, k1 ^ 0x7465646279746573u64,
        0u64, 0usize, 0usize, compression, finalization)
}
pub fn sip13(k0: u64, k1: u64): SipHasher { sip_with_rounds(k0, k1, 1u32, 3u32) }
pub fn sip24(k0: u64, k1: u64): SipHasher { sip_with_rounds(k0, k1, 2u32, 4u32) }
fn sip_absorb(hasher: mut SipHasher, word: u64): Unit {
    hasher.v3 = hasher.v3 ^ word
    var round = 0u32
    while round < hasher.compression { sip_round(mut hasher); round += 1u32 }
    hasher.v0 = hasher.v0 ^ word
}
extend SipHasher implements Hasher {
    mut fn write(bytes: read [u8]): Unit {
        var i = 0usize
        while i < bytes.len() {
            self.tail = self.tail | ((bytes[i] as u64) << ((self.tail_length * 8usize) as u64))
            self.tail_length += 1usize
            self.length += 1usize
            if self.tail_length == 8usize {
                let word = self.tail
                self.tail = 0u64
                self.tail_length = 0usize
                sip_absorb(mut self, word)
            }
            i += 1usize
        }
    }
    // Finalizes a scratch copy of the state, so more input can follow.
    fn finish(): u64 {
        var scratch = SipHasher(self.v0, self.v1, self.v2, self.v3, self.tail, self.tail_length,
                             self.length, self.compression, self.finalization)
        let last = (((self.length as u64) & 0xffu64) << 56u64) | self.tail
        sip_absorb(mut scratch, last)
        scratch.v2 = scratch.v2 ^ 0xffu64
        var round = 0u32
        while round < scratch.finalization { sip_round(mut scratch); round += 1u32 }
        scratch.v0 ^ scratch.v1 ^ scratch.v2 ^ scratch.v3
    }
}
extend u8 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u8(self) }
}
extend u16 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u16(self) }
}
extend u32 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u32(self) }
}
extend u64 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u64(self) }
}
extend u128 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u128(self) }
}
extend usize implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_usize(self) }
}
extend i8 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u8(self as u8) }
}
extend i16 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u16(self as u16) }
}
extend i32 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u32(self as u32) }
}
extend i64 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u64(self as u64) }
}
extend i128 implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u128(self as u128) }
}
extend isize implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_usize(self as usize) }
}
extend bool implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u8(self as u8) }
}
extend char implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u32(self as u32) }
}
extend Unit implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {}
}
// The 0xff terminator keeps ("ab", "c") distinct from ("a", "bc").
extend Text implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write(self.as_bytes())
        state.write_u8(0xffu8)
    }
}
extend Ordering implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write_u8(match self { Ordering.Less => 0u8, Ordering.Equal => 1u8, Ordering.Greater => 2u8 })
    }
}
// Length-prefixed so nested slices cannot collide by regrouping.
extend<T: Hash> [T] implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        state.write_usize(self.len())
        var i = 0usize
        while i < self.len() {
            self[i].hash(mut state)
            i += 1usize
        }
    }
}
extend<A: Hash, B: Hash> (A, B) implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        self.0.hash(mut state)
        self.1.hash(mut state)
    }
}
extend<T: Hash> T? implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit {
        match self {
            present(value) => { state.write_u8(1u8); value.hash(mut state) },
            none => { state.write_u8(0u8) }
        }
    }
}
