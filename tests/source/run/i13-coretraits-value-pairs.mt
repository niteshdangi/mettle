import core.clone.Clone
import core.cmp.{Ordering, Reverse}
import core.default.Default
import core.fmt
import core.hash
import core.hash.Hash

fn tuple_hash(value: read (i32, u8, bool)): u64 {
    var h = hash.fnv1a()
    value.hash(mut h)
    h.finish()
}

fn make<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    // Ordering is totally ordered: Less < Equal < Greater.
    if Ordering.Less.cmp(read Ordering.Equal) != Ordering.Less { return 1 }
    if Ordering.Greater.cmp(read Ordering.Equal) != Ordering.Greater { return 2 }
    if Ordering.Equal.cmp(read Ordering.Equal) != Ordering.Equal { return 3 }
    if Ordering.Less.cmp(read Ordering.Greater) != Ordering.Less { return 4 }
    if Ordering.Greater.cmp(read Ordering.Less) != Ordering.Greater { return 5 }
    if !(Ordering.Less < Ordering.Greater) || Ordering.Equal >= Ordering.Greater { return 6 }

    // Wide integers and floats clone, integers default to zero.
    if 7i128.clone() != 7i128 || 8u128.clone() != 8u128 { return 7 }
    if 1.5f32.clone() != 1.5f32 || 2.5f64.clone() != 2.5f64 { return 8 }
    if make<i128>() != 0i128 || make<u128>() != 0u128 { return 9 }

    // Reverse: clone, default and Debug.
    let flipped = Reverse(3i32).clone()
    if flipped.value != 3i32 { return 10 }
    if make<Reverse<i32>>().value != 0i32 { return 11 }
    var bytes = [0u8; 32]
    var out = fmt.buffer_writer(mut bytes)
    var f = fmt.formatter(mut out, fmt.spec())
    match capture Reverse<i32>.(fmt.Debug).fmt(Reverse(5i32), mut f) {
        success(_) => {},
        failure(_) => { return 12 }
    }
    let used = out.len()
    match fmt.written_text(read bytes, used) {
        present(text) => { if text != "Reverse(5)" { return 13 } },
        none => { return 13 }
    }

    // Three-element tuples: lexicographic order, equality, hash, clone, default.
    let a = (1, 2u8, true)
    let b = (1, 2u8, false)
    let c = (1, 3u8, false)
    if a == b || !(a != b) { return 14 }
    if !(b < a) || !(a < c) || a.cmp(read c) != Ordering.Less { return 15 }
    if a.partial_cmp(read a) != present(Ordering.Equal) { return 16 }
    if tuple_hash(a) != tuple_hash(a.clone()) || tuple_hash(a) == tuple_hash(b) { return 17 }
    let zero = make<(i32, u8, bool)>()
    if zero.0 != 0 || zero.1 != 0u8 || zero.2 { return 18 }
    0
}
