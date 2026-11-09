// profiles: debug release
import alloc.vec.List
import core.cmp.Ordering
import core.convert.From

fn sample(): List<i32> {
    let arr = [5, 1, 4, 2, 3, 0]
    List<i32>.(From<read [i32; 6]>).from(read arr)
}

fn found_at(result: (usize throws usize), index: usize): bool {
    match take result {
        success(i) => i == index,
        failure(_) => false
    }
}

fn main(): i32 {
    var v = sample()
    if *v.first().unwrap() != 5 || *v.last().unwrap() != 0 { return 1 }
    *v.first_mut().unwrap() = 6
    *v.last_mut().unwrap() = 9
    if v[0usize] != 6 || v[5usize] != 9 { return 2 }
    if *v.get(1usize).unwrap() != 1 || v.get(9usize).is_present() { return 3 }
    *v.get_mut(1usize).unwrap() = 1
    unsafe { if *v.get_unchecked(2usize) != 4 { return 4 } }
    unsafe { *v.get_unchecked_mut(2usize) = 4 }

    let (head, tail) = v.split_first().unwrap()
    if *head != 6 || tail.len() != 5usize { return 5 }
    let (last_item, front_part) = v.split_last().unwrap()
    if *last_item != 9 || front_part.len() != 5usize { return 6 }
    let (mh, mt) = v.split_first_mut().unwrap()
    *mh = 7
    if mt.len() != 5usize || v[0usize] != 7 { return 7 }
    let (ml, mi) = v.split_last_mut().unwrap()
    *ml = 8
    if mi.len() != 5usize || v[5usize] != 8 { return 8 }

    let (left, right) = v.split_at(2usize)
    if left.len() != 2usize || right[0usize] != 4 { return 9 }
    if v.split_at_checked(9usize).is_present() { return 10 }
    var fresh_m = sample()
    unsafe {
        let (a, b) = v.split_at_unchecked(3usize)
        if a.len() != 3usize || b.len() != 3usize { return 11 }
    }
    let (ml2, mr2) = v.split_at_mut(3usize)
    ml2[0usize] = 70
    mr2[0usize] = 40
    if v[0usize] != 70 || v[3usize] != 40 { return 12 }
    if v.split_at_mut_checked(10usize).is_present() { return 13 }
    var fresh_m = sample()
    unsafe {
        let (a, b) = v.split_at_mut_unchecked(1usize)
        a[0usize] = 71
        if b.len() != 5usize { return 14 }
    }

    var w = sample()
    w.fill(3)
    if w[4usize] != 3 { return 15 }
    var counter = 0
    w.fill_with(fn(): i32 { counter += 1; counter })
    if w[5usize] != 6 { return 16 }
    w.rotate_left(1usize)
    w.rotate_right(1usize)
    if w[0usize] != 1 { return 17 }
    w.reverse()
    w.swap(0usize, 5usize)
    if w[0usize] != 1 { return 18 }
    w.copy_from_slice(read [9, 9, 9, 9, 9, 9])
    w.copy_within(0usize, 2usize, 4usize)
    if w[5usize] != 9 { return 19 }
    w.clone_from_slice(read [1, 2, 3, 4, 5, 6])
    var swap_target = sample()
    w.swap_with_slice(mut swap_target)
    if w[0usize] != 5 { return 20 }

    var s = sample()
    s.sort_unstable()
    if !s.is_sorted() || !found_at(capture s.binary_search(read 4), 4usize) { return 21 }
    s.sort_unstable_by(fn(a: read i32, b: read i32): Ordering { b.cmp(read a) })
    if s[0usize] != 5 { return 22 }
    s.sort_unstable_by_key(fn(a: read i32): i32 { -a })
    if s[0usize] != 5 { return 23 }
    if !s.is_sorted_by(fn(a: read i32, b: read i32): bool { a >= b }) { return 24 }
    if !s.is_sorted_by_key(fn(a: read i32): i32 { -a }) { return 25 }
    if s.partition_point(fn(a: read i32): bool { a > 2 }) != 3usize { return 26 }
    var asc = sample()
    asc.sort_unstable()
    if !found_at(capture asc.binary_search_by_key(read 5, fn(a: read i32): i32 { a }), 5usize) { return 27 }
    if !found_at(capture asc.binary_search_by(fn(a: read i32): Ordering { a.cmp(read 4) }), 4usize) { return 28 }
    var nth = sample()
    nth.select_nth_unstable(2usize)
    nth.select_nth_unstable_by(0usize, fn(a: read i32, b: read i32): Ordering { a.cmp(read b) })
    nth.select_nth_unstable_by_key(1usize, fn(a: read i32): i32 { a })
    if nth[1usize] != 1 { return 29 }

    if !sample().starts_with(read [5, 1]) || !sample().ends_with(read [3, 0]) { return 30 }
    if sample().strip_prefix(read [5]).unwrap().len() != 5usize { return 31 }
    if sample().strip_suffix(read [0]).unwrap().len() != 5usize { return 32 }
    if !sample().contains(read 4) { return 33 }

    let base = sample()
    var chunks_total = 0
    for c in base.chunks(4usize) { chunks_total += c.len() }
    if chunks_total != 6 { return 34 }
    var exact_count = 0
    for c in base.chunks_exact(4usize) { exact_count += 1 }
    if exact_count != 1 { return 35 }
    var rchunk_first = 0
    for c in base.rchunks(4usize) { rchunk_first = c.len() }
    if rchunk_first != 2usize { return 36 }
    var rexact = 0
    for c in base.rchunks_exact(4usize) { rexact += 1 }
    if rexact != 1 { return 37 }
    var windows = 0
    for win in base.windows(3usize) { windows += 1 }
    if windows != 4 { return 38 }
    var cm = sample()
    for c in cm.chunks_mut(2usize) { c[0usize] = 0 }
    for c in cm.chunks_exact_mut(2usize) { c[1usize] = 1 }
    for c in cm.rchunks_mut(2usize) { c[0usize] = 2 }
    for c in cm.rchunks_exact_mut(2usize) { c[1usize] = 3 }
    if cm[0usize] != 2 || cm[1usize] != 3 || cm[5usize] != 3 { return 39 }
    if sample().chunk(0usize, 2usize).unwrap().len() != 2usize { return 40 }
    if sample().subslice(1usize, 3usize).unwrap().len() != 2usize { return 41 }

    var pieces = 0
    for piece in base.split(fn(a: read i32): bool { a == 4 }) { pieces += 1 }
    if pieces != 2 { return 42 }
    var sp_m = sample()
    for piece in sp_m.split_mut(fn(a: read i32): bool { a == 4 }) { pieces += 1 }
    if pieces != 4 { return 43 }
    var sp_i = 0
    for piece in base.splitn(2usize, fn(a: read i32): bool { a == 4 }) { sp_i += 1 }
    if sp_i != 2 { return 44 }
    var rsp = 0
    for piece in base.rsplit(fn(a: read i32): bool { a == 4 }) { rsp += 1 }
    if rsp != 2 { return 45 }
    var rspn = 0
    for piece in base.rsplitn(2usize, fn(a: read i32): bool { a == 4 }) { rspn += 1 }
    if rspn != 2 { return 46 }
    var inc = 0
    for piece in base.split_inclusive(fn(a: read i32): bool { a == 4 }) { inc += 1 }
    if inc != 2 { return 47 }
    var inc_m = sample()
    for piece in inc_m.split_inclusive_mut(fn(a: read i32): bool { a == 4 }) { inc += 1 }
    if inc != 4 { return 48 }
    var runs = 0
    for run in base.chunk_by(fn(a: read i32, b: read i32): bool { a < b }) { runs += 1 }
    if runs != 4 { return 49 }
    var runs_m = sample()
    for run in runs_m.chunk_by_mut(fn(a: read i32, b: read i32): bool { a < b }) { runs += 1 }
    if runs != 8 { return 50 }

    let fresh = sample()
    if fresh.first_chunk<2>().unwrap()[1usize] != 1 { return 51 }
    if fresh.last_chunk<2>().unwrap()[0usize] != 3 { return 52 }
    let (sf, sr) = fresh.split_first_chunk<2>().unwrap()
    if sf[1usize] != 1 || sr.len() != 4usize { return 53 }
    let (sr2, sl) = fresh.split_last_chunk<2>().unwrap()
    if sl[1usize] != 0 || sr2.len() != 4usize { return 54 }
    var fm = sample()
    let fcm = fm.first_chunk_mut<2>().unwrap()
    fcm[0usize] = 8
    let lcm = fm.last_chunk_mut<2>().unwrap()
    lcm[1usize] = 8
    if fm[0usize] != 8 || fm[5usize] != 8 { return 55 }
    let (sfm, srm) = fm.split_first_chunk_mut<2>().unwrap()
    sfm[1usize] = 9
    if srm.len() != 4usize { return 56 }
    let (slm, slm_tail) = fm.split_last_chunk_mut<2>().unwrap()
    slm_tail[0usize] = 9
    if slm.len() != 4usize || fm[1usize] != 9 || fm[4usize] != 9 { return 57 }

    if fresh.as_array<6>().unwrap()[5usize] != 0 { return 58 }
    var am_src = sample()
    let am = am_src.as_mut_array<6>().unwrap()
    am[0usize] = 1
    if am_src[0usize] != 1 { return 59 }

    let (chunks4, rem4) = fresh.as_chunks<4>()
    if chunks4.len() != 1usize || rem4.len() != 2usize { return 60 }
    let (rrem, rchunks4) = fresh.as_rchunks<4>()
    if rchunks4.len() != 1usize || rrem.len() != 2usize { return 61 }
    var cm_src = sample()
    let (cm_chunks, _cm_rem) = cm_src.as_chunks_mut<4>()
    cm_chunks[0usize][0usize] = 0
    if cm_src[0usize] != 0 { return 62 }
    let (_rm_rem, rm_chunks) = cm_src.as_rchunks_mut<4>()
    rm_chunks[0usize][3usize] = 7
    if cm_src[5usize] != 7 { return 63 }
    var fresh_m = sample()
    unsafe {
        if fresh.as_chunks_unchecked<3>().len() != 2usize { return 64 }
        if fresh_m.as_chunks_unchecked_mut<3>().len() != 2usize { return 65 }
    }
    let pr = fresh.as_ptr_range()
    if pr.start != fresh.as_ptr() { return 66 }
    0
}
