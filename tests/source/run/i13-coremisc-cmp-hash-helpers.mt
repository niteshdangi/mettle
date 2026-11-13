// profiles: debug release
// Evidence for the comparison free functions, Descending, and the Hash, Hasher
// and BuildHasher helpers.

import core.clone.Clone
import core.default.Default
import core.cmp
import core.cmp.{Ord, Ordering, PartialEq, PartialOrd, Descending}
import core.hash.{BuildHasher, Fnv1a, Hash, Hasher, fnv1a, hash_one}
import std.panic.{catch_panic, CatchResult}

type Factory {}
extend Factory implements BuildHasher {
    type Hasher = Fnv1a
    fn build_hasher(): Fnv1a { fnv1a() }
}

type NotCopy { value: i32 }

type Bytes { data: i32 }
extend Bytes implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { state.write_i32(self.data) }
}

fn checks_cmp(): i32 {
    if cmp.min(3i32, 5i32) != 3 || cmp.max(3i32, 5i32) != 5 { return 1 }
    if cmp.min(4i32, 4i32) != 4 || cmp.max(-2i32, -7i32) != -2 { return 2 }
    if cmp.clamp(9i32, 0i32, 6i32) != 6 || cmp.clamp(-1i32, 0i32, 6i32) != 0 { return 3 }
    match take catch_panic(fn(): i32 { cmp.clamp(3i32, 4i32, 2i32); 0 }) {
        CatchResult.Panicked(info) => { if info.code() != 101 { return 12 } },
        CatchResult.Returned(_) => { return 12 }
    }
    let low = Descending(2i32)
    let high = Descending(9i32)
    if !(high < low) || low < high || !(low.clone() == Descending(2i32)) { return 4 }
    let defaulted: Descending<i32> = Descending<i32>.(Default).default()
    if defaulted.value != 0 { return 10 }
    if hash_one(read low) != hash_one(read 2i32) { return 11 }
    if low.cmp(read high) != Ordering.Greater { return 5 }
    if low.partial_cmp(read high) != present(Ordering.Greater) { return 6 }
    if low.value != 2 || high.value != 9 { return 7 }
    let move_only = Descending(NotCopy(1))
    if move_only.value.value != 1 { return 13 }
    if !(2i32.lt(read 3)) || !(3i32.le(read 3)) || 3i32.gt(read 3) || 3i32.ge(read 4) { return 8 }
    if 3i32.ne(read 4) != true || 3i32.ne(read 3) { return 9 }
    0
}

fn checks_hash(): i32 {
    let first = hash_one(read 7i32)
    if first != hash_one(read 7i32) || first == hash_one(read 8i32) { return 20 }
    if hash_one(read Bytes(3)) != hash_one(read Bytes(3)) { return 21 }
    var state = fnv1a()
    state.write(read [1u8, 2u8])
    let direct = state.finish()
    var again = fnv1a()
    again.write_u8(1u8)
    again.write_u8(2u8)
    if again.finish() != direct { return 22 }
    var wide = fnv1a()
    wide.write_u16(0x0102u16)
    wide.write_u32(0x01020304u32)
    wide.write_u64(0x0102030405060708u64)
    wide.write_u128(3u128)
    wide.write_i8(-1i8)
    wide.write_i16(-2i16)
    wide.write_i32(-3i32)
    wide.write_i64(-4i64)
    wide.write_i128(-5i128)
    wide.write_usize(6usize)
    wide.write_isize(-7isize)
    var expected = fnv1a()
    expected.write(read [
        0x02u8, 0x01,
        0x04, 0x03, 0x02, 0x01,
        0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
        0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0xff,
        0xfe, 0xff,
        0xfd, 0xff, 0xff, 0xff,
        0xfc, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x06, 0, 0, 0, 0, 0, 0, 0,
        0xf9, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    ])
    if wide.finish() != expected.finish() { return 23 }
    let factory = Factory()
    if factory.build_hasher().finish() != fnv1a().finish() { return 24 }
    0
}

fn main(): i32 {
    let cmp_status = checks_cmp()
    if cmp_status != 0 { return cmp_status }
    checks_hash()
}
