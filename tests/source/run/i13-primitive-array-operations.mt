// profiles: debug release
import core.cmp.{PartialEq, Ord, Ordering}
import core.default.Default
import core.clone.Clone
import core.hash.{Fnv1a, Hash, Hasher, fnv1a}

fn make<T: Default>(): T { T.(Default).default() }

type NoDefault { value: i32 }

fn digest<T: Hash>(read value: T): u64 {
    var h = fnv1a()
    value.hash(mut h)
    h.finish()
}

fn main(): i32 {
    let zeros: [i32; 5] = make()
    if zeros != [0i32, 0i32, 0i32, 0i32, 0i32] { return 1 }
    let defaults: [u8; 32] = make()
    for value in defaults { if value != 0u8 { return 12 } }
    let wide = [0u8; 40]
    let wide_view: read [u8] = read wide
    if wide[39usize] != 0u8 || wide_view.len() != 40usize { return 2 }
    let flags: [bool; 1] = make()
    if flags[0usize] { return 3 }

    let a = [1i32, 2i32, 3i32]
    let dup = a.clone()
    if dup != a || dup.cmp(read a) != Ordering.Equal || !(a <= dup) { return 4 }
    if digest(read a) != digest(read dup) || digest(read a) == digest([1i32, 2i32, 4i32]) { return 5 }

    let refs = a.each_ref()
    if *refs[2usize] != 3 { return 6 }
    var m = [4i32, 5i32]
    let mrefs = m.each_mut()
    *mrefs[0usize] = 9
    if m[0usize] != 9 { return 7 }

    let pair: ([i32; 2], bool) = (pair_of_twos(), true)
    if pair.0[1usize] != 2 || !pair.1 { return 8 }
    if [1u8, 2u8].len() != 2usize || [1u8, 2u8].is_empty() { return 9 }
    let empty_local: [u8; 0] = make()
    if empty_local.len() != 0usize || !empty_local.is_empty() { return 10 }
    let empty_nondefault: [NoDefault; 0] = make()
    if !empty_nondefault.is_empty() { return 13 }
    if wide.len() != 40usize || flags.is_empty() { return 11 }
    0
}

fn pair_of_twos(): [i32; 2] { [2i32, 2i32] }
