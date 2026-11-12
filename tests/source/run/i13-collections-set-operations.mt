// profiles: debug release
import alloc.hash_map
import alloc.vec
import core.clone.Clone
import core.cmp.Eq
import core.default.Default
import core.fmt.{Debug, Error, buffer_writer, formatter, spec, written_text}
import core.iter.{ExtendItems, FromItems, OwnedIterable, ExactSizeIterator}

fn default_value<T: Default>(): T { T.(Default).default() }
fn require_debug<T: Debug>(read value: T): bool { true }
fn require_eq<T: Eq>(read value: T): bool { true }
fn exact_len<I: ExactSizeIterator>(read items: I): usize {
    I.(ExactSizeIterator).len(items)
}

fn render<T: Debug>(read value: T, mut buffer: [u8]): usize throws Error {
    var out = buffer_writer(mut buffer)
    var f = formatter(mut out, spec())
    try value.fmt(mut f)
    out.len()
}

fn set_of(first: i32, second: i32, third: i32): hash_map.Set<i32> {
    var out = hash_map.set_new<i32>()
    out.insert(first)
    out.insert(second)
    out.insert(third)
    out
}


fn run(): i32 throws Error {
    var buffer = [0u8; 64]

    // Construction, membership and capacity.
    var empty = hash_map.set_new<i32>()
    if !empty.is_empty() || empty.len() != 0usize || empty.contains(1) { return 1 }
    var defaulted: hash_map.Set<i32> = default_value<hash_map.Set<i32>>()
    if !defaulted.is_empty() { return 2 }
    var set = hash_map.set_new<i32>()
    set.reserve(6usize)
    if set.capacity() < 6usize { return 3 }
    set.reserve_exact(1usize)
    match capture set.try_reserve(2usize) { success(_) => {}, failure(_) => { return 4 } }
    match capture set.try_reserve_exact(2usize) { success(_) => {}, failure(_) => { return 5 } }
    match capture set.try_reserve(0xffffffffffffffffusize) { success(_) => { return 6 }, failure(_) => {} }
    set.shrink_to(0usize)
    set.shrink_to_fit()

    // Insertion reports whether the value was new; replace and take return the stored key.
    if !set.insert(1) || !set.insert(2) || !set.insert(3) { return 10 }
    if set.insert(2) { return 11 }
    if set.len() != 3usize || !set.contains(3) || set.contains(4) { return 12 }
    match set.get(2) {
        present(stored) => { if *stored != 2 { return 13 } },
        none => { return 14 }
    }
    match set.replace(2) {
        present(old) => { if old != 2 { return 15 } },
        none => { return 16 }
    }
    match take set.`take`(1) {
        present(old) => { if old != 1 { return 17 } },
        none => { return 18 }
    }
    if set.remove(1) || !set.remove(2) || set.len() != 1usize { return 19 }
    match capture set.try_insert(7) {
        success(added) => { if !added { return 20 } },
        failure(_) => { return 20 }
    }
    set.insert(8)
    set.insert(9)

    // Iteration and retention.
    var total = 0
    for value in set.iter() { total += *value }
    if total != 3 + 7 + 8 + 9 { return 21 }
    var owned = 0
    var drain = set.drain()
    if exact_len(read drain) != 4usize { return 53 }
    for value in drain { owned += value }
    if owned != 27 || !set.is_empty() { return 22 }
    var debug_set = hash_map.set_new<i32>()
    debug_set.insert(1)
    var debug_drain = debug_set.drain()
    if !require_debug(read debug_drain) { return 26 }
    set.insert(1)
    set.insert(2)
    set.insert(3)
    set.insert(4)
    var visits = 0
    set.retain(fn(read value: i32): bool {
        visits += 1
        value % 2 == 0
    })
    if visits != 4 || set.len() != 2usize || !set.contains(2) || !set.contains(4) { return 23 }
    var extracted = 0
    for value in set.extract_if(fn(read value: i32): bool { value == 2 }) {
        extracted += value
    }
    if extracted != 2 || set.len() != 1usize { return 24 }
    set.clear()
    if !set.is_empty() { return 25 }

    // Set algebra: each operation yields the matching elements of the operands.
    let left = set_of(1, 2, 3)
    let right = set_of(3, 4, 5)
    var union_total = 0
    var union_count = 0
    for value in left.`union`(read right) {
        union_total += *value
        union_count += 1
    }
    if union_count != 5 || union_total != 15 { return 30 }
    var common = 0
    for value in left.intersection(read right) { common += *value }
    if common != 3 { return 31 }
    var only_left = 0
    for value in left.difference(read right) { only_left += *value }
    if only_left != 3 { return 32 }
    var exclusive = 0
    for value in left.symmetric_difference(read right) { exclusive += *value }
    if exclusive != 12 { return 33 }
    let subset = set_of(2, 3, 0)
    if !set_of(2, 3, 3).is_subset(read left) || subset.is_subset(read left) { return 34 }
    if !left.is_superset(read set_of(1, 3, 3)) || left.is_superset(read right) { return 35 }
    if !left.is_disjoint(read set_of(9, 10, 11)) || left.is_disjoint(read right) { return 36 }

    // Clone, equality, Debug and collection construction.
    let duplicate = left.clone()
    if !require_eq(read duplicate) || duplicate != left || duplicate.len() != 3usize { return 40 }
    if left == right { return 41 }
    let written = try render(read left, mut buffer)
    match written_text(read buffer, written) {
        present(text) => {
            if text != "{1, 2, 3}" && text != "{1, 3, 2}" &&
                text != "{2, 1, 3}" && text != "{2, 3, 1}" &&
                text != "{3, 1, 2}" && text != "{3, 2, 1}" { return 42 }
        },
        none => { return 43 }
    }
    var keyed = vec.new<i32>()
    keyed.push(5)
    keyed.push(5)
    keyed.push(6)
    var built = hash_map.Set<i32>.(FromItems<i32>).from_iter(keyed)
    if built.len() != 2usize || !built.contains(6) { return 44 }
    var more = vec.new<i32>()
    more.push(7)
    built.extend(more)
    if built.len() != 3usize { return 45 }

    // Operators build new sets; the operands are left unchanged.
    let joined = left | right
    if joined.len() != 5usize || !joined.contains(1) || !joined.contains(5) { return 46 }
    let meet = left & right
    if meet.len() != 1usize || !meet.contains(3) { return 47 }
    let diff = left - right
    if diff.len() != 2usize || diff.contains(3) { return 48 }
    let sym = left ^ right
    if sym.len() != 4usize || sym.contains(3) || !sym.contains(5) { return 49 }
    if left.len() != 3usize || right.len() != 3usize { return 50 }
    return 0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 99 }
}
