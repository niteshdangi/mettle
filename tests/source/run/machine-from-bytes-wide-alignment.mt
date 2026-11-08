// profiles: debug release
import core.cmp.PartialEq
// from_*_bytes reads its byte-array temporary at the array's alignment, not
// at the 16-byte ABI alignment of 128-bit integers (debug previously faulted).
fn bytes(): [u8; 16] {
    [1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8, 16u8]
}

fn main(): i32 {
    let value = u128.from_le_bytes(bytes())
    if value.to_le_bytes() != bytes() { return 1 }
    if u128.from_be_bytes(bytes()) != value.swap_bytes() { return 2 }
    if i128.from_ne_bytes(bytes()).cast_unsigned() != value { return 3 }
    if u64.from_le_bytes([1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) != 1u64 { return 4 }
    0
}
