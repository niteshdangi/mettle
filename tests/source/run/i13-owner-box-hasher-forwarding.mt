import alloc.boxed
import core.hash.Hasher

type SpecializedHasher { calls: u64 }

extend SpecializedHasher implements Hasher {
    mut fn write(read bytes: [u8]): Unit {
        if bytes.len() == 1usize && bytes[0usize] == 17u8 { self.calls |= 1u64 }
    }
    mut fn write_u8(value: u8): Unit { if value == 1u8 { self.calls |= 2u64 } }
    mut fn write_u16(value: u16): Unit { if value == 2u16 { self.calls |= 4u64 } }
    mut fn write_u32(value: u32): Unit { if value == 3u32 { self.calls |= 8u64 } }
    mut fn write_u64(value: u64): Unit { if value == 4u64 { self.calls |= 16u64 } }
    mut fn write_u128(value: u128): Unit { if value == 5u128 { self.calls |= 32u64 } }
    mut fn write_usize(value: usize): Unit { if value == 6usize { self.calls |= 64u64 } }
    mut fn write_i8(value: i8): Unit { if value == -1i8 { self.calls |= 128u64 } }
    mut fn write_i16(value: i16): Unit { if value == -2i16 { self.calls |= 256u64 } }
    mut fn write_i32(value: i32): Unit { if value == -3i32 { self.calls |= 512u64 } }
    mut fn write_i64(value: i64): Unit { if value == -4i64 { self.calls |= 1024u64 } }
    mut fn write_i128(value: i128): Unit { if value == -5i128 { self.calls |= 2048u64 } }
    mut fn write_isize(value: isize): Unit { if value == -6isize { self.calls |= 4096u64 } }
    fn finish(): u64 { self.calls }
}

fn exercise<H: Hasher>(mut hasher: H): Unit {
    let bytes = [17u8]
    hasher.write(read bytes)
    hasher.write_u8(1u8)
    hasher.write_u16(2u16)
    hasher.write_u32(3u32)
    hasher.write_u64(4u64)
    hasher.write_u128(5u128)
    hasher.write_usize(6usize)
    hasher.write_i8(-1i8)
    hasher.write_i16(-2i16)
    hasher.write_i32(-3i32)
    hasher.write_i64(-4i64)
    hasher.write_i128(-5i128)
    hasher.write_isize(-6isize)
}

fn main(): i32 {
    var hasher = boxed.new(SpecializedHasher(0u64))
    exercise(mut hasher)
    if hasher.finish() != 8191u64 { return 1 }
    0
}
