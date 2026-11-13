import core.cmp
import core.cmp.Ordering
import core.cmp.Ord
import core.cmp.PartialOrd
import core.hash
import core.hash.Hash
import core.hash.Hasher
import core.text.Text
import core.option

fn slice_hash(read items: [i32]): u64 {
    var h = hash.fnv1a()
    items.hash(mut h)
    h.finish()
}

fn pair_hash(read first: Text, read second: Text): u64 {
    var h = hash.fnv1a()
    first.hash(mut h)
    second.hash(mut h)
    h.finish()
}

fn main(): i32 {
    let a = (1, 2u8)
    let b = (1, 3u8)
    if !(a < b) || a == b || !(a != b) { return 1 }
    if a.cmp(read b) != Ordering.Less { return 2 }
    let x = [1, 2, 3]
    let y = [1, 2, 4]
    let xs: read [i32] = read x
    let ys: read [i32] = read y
    if !(*xs < *ys) || *xs == *ys || !(*xs == *xs) { return 3 }
    let p: i32? = present(1)
    let n: i32? = none
    let q: i32? = present(2)
    if p == n || !(p == p) || !(n == n) || !(n < p) || !(p < q) || n.cmp(read p).is_ge() { return 4 }
    if !("abc" < "abd") || !("ab" < "abc") || "b" < "a" || !("\u{e9}" > "z") { return 5 }
    if cmp.min(3, 2) != 2 || cmp.max(3, 2) != 3 || cmp.clamp(9, 0, 5) != 5 || cmp.clamp(-9, 0, 5) != 0 || cmp.clamp(3, 0, 5) != 3 { return 6 }
    if cmp.max(1, 1) != 1 { return 7 }
    if Ordering.Less.reverse() != Ordering.Greater || Ordering.Equal.then(Ordering.Less) != Ordering.Less || Ordering.Greater.then(Ordering.Less) != Ordering.Greater { return 8 }
    if !(cmp.Descending(1) > cmp.Descending(2)) { return 9 }
    if 'a'.cmp(read 'b') != Ordering.Less || true.cmp(read false) != Ordering.Greater { return 10 }
    // Known vectors: SipHash-2-4 reference output and FNV-1a of "a"
    var h = hash.sip24(0x0706050403020100u64, 0x0f0e0d0c0b0a0908u64)
    if h.finish() != 0x726fdb47dd0e0e31u64 { return 11 }
    h.write_u8(0u8)
    if h.finish() != 0x74f839c593dc67fdu64 { return 12 }
    var f = hash.fnv1a()
    f.write("a".as_bytes())
    if f.finish() != 0xaf63dc4c8601ec8cu64 { return 13 }
    // Eq implies equal hashes; distinct values differ for these inputs
    if hash.hash_one(read a) != hash.hash_one(read (1, 2u8)) || hash.hash_one(read a) == hash.hash_one(read b) { return 14 }
    if pair_hash("abc", "x") != pair_hash("abc", "x") || pair_hash("abc", "x") == pair_hash("abd", "x") { return 15 }
    if slice_hash(xs) != slice_hash(read x) || slice_hash(xs) == slice_hash(ys) { return 16 }
    if hash.hash_one(read p) != hash.hash_one(read present(1)) || hash.hash_one(read p) == hash.hash_one(read n) { return 17 }
    // text and bytes are length-delimited: ("ab","c") differs from ("a","bc")
    if pair_hash("ab", "c") == pair_hash("a", "bc") { return 18 }
    if hash.hash_one(read cmp.Descending(42)) != hash.hash_one(read 42) { return 24 }
    let low = -170141183460469231731687303715884105728i128
    let same_low = -170141183460469231731687303715884105728i128
    let high = 340282366920938463463374607431768211455u128
    if !(low < 0i128) || !(0u128 < high) { return 19 }
    if low.cmp(read 0i128) != Ordering.Less || high.cmp(read 1u128) != Ordering.Greater { return 20 }
    if hash.hash_one(read low) != hash.hash_one(read same_low) ||
       hash.hash_one(read high) != hash.hash_one(read 340282366920938463463374607431768211455u128) { return 23 }
    let zero = 0.0f64
    let negative_zero = -0.0f64
    let nan = f64.from_bits(0x7ff8000000000042u64)
    if !(zero == negative_zero) || !zero.partial_cmp(read negative_zero).is_present() { return 21 }
    match nan.partial_cmp(read nan) {
        none => {},
        present(order) => { return 22 }
    }
    0
}
