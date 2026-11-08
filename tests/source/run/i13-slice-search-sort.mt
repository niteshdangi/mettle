// profiles: debug release
import core.cmp.Ordering

fn main(): i32 {
    // binary_search returns the match index or the insertion point.
    let sorted = [1, 3, 5, 7, 9]
    let s: read [i32] = read sorted
    match capture s.binary_search(7) {
        success(index) => { if index != 3usize { return 1 } },
        failure(_) => { return 1 }
    }
    match capture s.binary_search(4) {
        success(_) => { return 2 },
        failure(index) => { if index != 2usize { return 2 } }
    }
    match capture s.binary_search(0) {
        success(_) => { return 3 },
        failure(index) => { if index != 0usize { return 3 } }
    }
    match capture s.binary_search(10) {
        success(_) => { return 4 },
        failure(index) => { if index != 5usize { return 4 } }
    }
    let duplicates = [2, 2, 2, 4]
    let d: read [i32] = read duplicates
    match capture d.binary_search(2) {
        success(index) => { if index > 2usize { return 5 } },
        failure(_) => { return 5 }
    }
    match capture d.binary_search_by(fn(x: read i32): Ordering { x.cmp(4) }) {
        success(index) => { if index != 3usize { return 6 } },
        failure(_) => { return 6 }
    }
    let key = 10
    match capture s.binary_search_by_key(read key, fn(x: read i32): i32 { x }) {
        success(_) => { return 7 },
        failure(index) => { if index != 5usize { return 7 } }
    }

    // partition_point and the is_sorted family.
    if s.partition_point(fn(x: read i32): bool { x < 6 }) != 3usize { return 8 }
    if s.partition_point(fn(x: read i32): bool { x < 0 }) != 0usize { return 9 }
    if !s.is_sorted() || !s.is_sorted_by(fn(a: read i32, b: read i32): bool { a <= b }) {
        return 10
    }
    if !s.is_sorted_by_key(fn(x: read i32): i32 { x }) { return 11 }
    let unsorted = [3, 1, 2]
    let u: read [i32] = read unsorted
    if u.is_sorted() || u.is_sorted_by(fn(a: read i32, b: read i32): bool { a <= b }) { return 12 }

    // Sorting in place, with every comparator flavour.
    var values = [5, 1, 4, 2, 3]
    {
        let m = mut values
        m.sort_unstable()
    }
    if values[0usize] != 1 || values[4usize] != 5 { return 13 }
    {
        let m = mut values
        m.sort_unstable_by(fn(a: read i32, b: read i32): Ordering { b.cmp(a) })
    }
    if values[0usize] != 5 || values[4usize] != 1 { return 14 }
    {
        let m = mut values
        m.sort_unstable_by_key(fn(x: read i32): i32 { x })
    }
    if values[0usize] != 1 || values[2usize] != 3 { return 15 }

    // select_nth_unstable partitions around the requested rank.
    var selected = [9, 1, 7, 3, 5]
    {
        let m = mut selected
        let parts = take m.select_nth_unstable(2usize)
        if *parts.1 != 5 || parts.0.len() != 2usize || parts.2.len() != 2usize { return 16 }
    }
    var keyed = [9, 1, 7, 3, 5]
    {
        let m = mut keyed
        let parts = take m.select_nth_unstable_by_key(
            0usize,
            fn(value: read i32): i32 { value }
        )
        if *parts.1 != 1 || parts.0.len() != 0usize || parts.2.len() != 4usize { return 17 }
    }
    var ranked = [9, 1, 7, 3, 5]
    {
        let m = mut ranked
        let parts = take m.select_nth_unstable_by(
            4usize,
            fn(a: read i32, b: read i32): Ordering { a.cmp(b) }
        )
        if *parts.1 != 9 || parts.0.len() != 4usize { return 18 }
    }

    // Mutable element access through get_mut / first_mut / last_mut.
    var g = [10, 20, 30]
    {
        let m = mut g
        match take m.get_mut(1usize) {
            present(value) => { *value = 21 },
            none => { return 19 }
        }
        match take m.first_mut() {
            present(value) => { *value = 11 },
            none => { return 20 }
        }
        match take m.last_mut() {
            present(value) => { *value = 31 },
            none => { return 21 }
        }
        if m.get(3usize).is_present() || m.get_mut(3usize).is_present() { return 22 }
    }
    if g[0usize] != 11 || g[1usize] != 21 || g[2usize] != 31 { return 23 }

    // Prefix, suffix and membership.
    let hay = [1, 2, 3, 2, 1]
    let h: read [i32] = read hay
    if !h.starts_with([1, 2]) || !h.ends_with([2, 1]) || h.starts_with([2, 1]) { return 24 }
    if !h.contains(3) || h.contains(9) { return 25 }
    match h.strip_prefix([1, 2]) {
        present(rest) => { if rest.len() != 3usize || rest[0usize] != 3 { return 26 } },
        none => { return 26 }
    }
    match h.strip_suffix([2, 1]) {
        present(rest) => { if rest.len() != 3usize || rest[2usize] != 3 { return 27 } },
        none => { return 27 }
    }
    if h.strip_prefix([9]).is_present() || h.strip_suffix([9]).is_present() { return 28 }

    // Splitting into two views and into first/last parts.
    let parts = h.split_at(2usize)
    if parts.0.len() != 2usize || parts.1[0usize] != 3 { return 29 }
    match h.split_first() {
        present(first) => { if *first.0 != 1 || first.1.len() != 4usize { return 30 } },
        none => { return 30 }
    }
    match h.split_last() {
        present(last) => { if *last.0 != 1 || last.1.len() != 4usize { return 31 } },
        none => { return 31 }
    }

    // rsplit yields the same pieces as split, from the back.
    let commas = [1, 0, 2, 0, 3]
    let cs: read [i32] = read commas
    var from_back = cs.rsplit(fn(x: read i32): bool { x == 0 })
    match take from_back.next() {
        present(piece) => { if piece.len() != 1usize || piece[0usize] != 3 { return 32 } },
        none => { return 32 }
    }
    match take from_back.next() {
        present(piece) => { if piece.len() != 1usize || piece[0usize] != 2 { return 33 } },
        none => { return 33 }
    }
    match take from_back.next() {
        present(piece) => { if piece.len() != 1usize || piece[0usize] != 1 { return 34 } },
        none => { return 34 }
    }
    if from_back.next().is_present() { return 35 }

    // Rotation, reversal, and in-place copies.
    var r = [1, 2, 3, 4, 5]
    {
        let m = mut r
        m.rotate_left(2usize)
    }
    if r[0usize] != 3 || r[4usize] != 2 { return 36 }
    {
        let m = mut r
        m.rotate_right(1usize)
    }
    if r[0usize] != 2 || r[4usize] != 1 { return 37 }
    {
        let m = mut r
        m.swap(0usize, 4usize)
        m.reverse()
    }
    if r[0usize] != 2 || r[1usize] != 5 || r[4usize] != 1 { return 38 }
    {
        let m = mut r
        m.copy_within(0usize, 2usize, 3usize)
    }
    if r[3usize] != 2 || r[4usize] != 5 { return 39 }
    {
        let m = mut r
        m.fill_with(fn(): i32 { 7 })
    }
    if r[2usize] != 7 || r[4usize] != 7 { return 40 }

    var left = [1, 2]
    var right = [3, 4]
    {
        let a = mut left
        let b = mut right
        a.swap_with_slice(b)
    }
    if left[0usize] != 3 || right[1usize] != 2 { return 41 }

    var copied = [0, 0]
    let source = [5, 6]
    {
        let out = mut copied
        out.copy_from_slice(read source)
    }
    if copied[0usize] != 5 || copied[1usize] != 6 { return 42 }
    var cloned = [0, 0]
    {
        let out = mut cloned
        out.clone_from_slice(read source)
    }
    if cloned[1usize] != 6 { return 43 }

    // ASCII helpers on byte slices.
    var word = [72u8, 105u8]
    if !word.eq_ignore_ascii_case([104u8, 73u8]) { return 44 }
    {
        let m = mut word
        m.make_ascii_lowercase()
    }
    if word[0usize] != 104u8 || word[1usize] != 105u8 { return 45 }
    {
        let m = mut word
        m.make_ascii_uppercase()
    }
    if word[0usize] != 72u8 || word[1usize] != 73u8 { return 46 }
    let padded = [32u8, 65u8, 32u8]
    let p: read [u8] = read padded
    if p.trim_ascii().len() != 1usize || p.trim_ascii()[0usize] != 65u8 { return 47 }
    if p.trim_ascii_start().len() != 2usize || p.trim_ascii_end().len() != 2usize { return 48 }
    if !p.is_ascii() { return 49 }
    0
}
