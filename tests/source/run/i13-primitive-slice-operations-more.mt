// profiles: debug release
import alloc.vec
import alloc.vec.List
import core.cmp.{Ord, Ordering}

fn set_pair<region r>(take pair: [mut i32 from r; 2] from r) {
    *pair[0usize] = 11
    *pair[1usize] = 31
}

fn main(): i32 {
    let base = [3i32, 1i32, 2i32]
    let view: read [i32] = read base
    let copied: List<i32> = view.to_vec()
    if copied.len() != 3usize || copied[0usize] != 3 { return 1 }
    let twice: List<i32> = view.repeat(2usize)
    if twice.len() != 6usize || twice[3usize] != 3 || twice[5usize] != 2 { return 2 }
    if view.repeat(0usize).len() != 0usize { return 3 }

    var s = [3i32, 1i32, 2i32]
    let m: mut [i32] = mut s
    m.sort_by(fn(read a: i32, read b: i32): Ordering { b.cmp(read a) })
    if m[0usize] != 3 || m[2usize] != 1 { return 4 }
    m.sort_by_key(fn(read x: i32): i32 { x })
    if m[0usize] != 1 || m[2usize] != 3 { return 5 }
    m.sort_by_cached_key(fn(read x: i32): i32 { -x })
    if m[0usize] != 3 || m[2usize] != 1 { return 6 }

    let parts = m.split_at_mut(1usize)
    parts.0[0usize] = 8
    parts.1[1usize] = 9
    if m[0usize] != 8 || m[2usize] != 9 { return 7 }

    match take m.split_first_mut() {
        present(pair) => { *pair.0 = 5 },
        none => { return 8 }
    }
    if m[0usize] != 5 { return 9 }

    let fronts = view.as_chunks<2usize>()
    if fronts.0.len() != 1usize || fronts.1.len() != 1usize { return 10 }

    let pieces = [[1i32, 2i32], [3i32, 4i32]]
    let piece_view: read [[i32; 2]] = read pieces
    let flat: List<i32> = piece_view.concat()
    if flat.len() != 4usize || flat[3usize] != 4 { return 11 }
    let glued: List<i32> = piece_view.join(read [0])
    if glued.len() != 5usize || glued[2usize] != 0 || glued[4usize] != 4 { return 12 }

    var g = [10i32, 20i32, 30i32]
    let gm: mut [i32] = mut g
    let picks_0_2 = [0usize, 2usize]
    match take capture gm.get_disjoint_mut(read picks_0_2) {
        success(pair) => { set_pair(take pair) },
        failure(_) => { return 13 }
    }
    if gm[0usize] != 11 || gm[2usize] != 31 { return 14 }
    let picks_1_1 = [1usize, 1usize]
    match capture gm.get_disjoint_mut(read picks_1_1) {
        success(_) => { return 15 },
        failure(_) => {}
    }
    let picks_0_9 = [0usize, 9usize]
    match capture gm.get_disjoint_mut(read picks_0_9) {
        success(_) => { return 16 },
        failure(_) => {}
    }
    0
}
