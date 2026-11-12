// profiles: debug release
import alloc.btree
import alloc.vec
import core.clone.Clone
import core.cmp.{Eq, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.fmt.{Debug, Error, buffer_writer, formatter, spec, written_text}
import core.hash.hash_one
import core.iter.{ExtendItems, FromItems, OwnedIterable}

fn default_value<T: Default>(): T { T.(Default).default() }
fn require_eq<T: Eq>(read value: T): bool { true }

fn render<T: Debug>(read value: T, mut buffer: [u8]): usize throws Error {
    var out = buffer_writer(mut buffer)
    var f = formatter(mut out, spec())
    try value.fmt(mut f)
    out.len()
}

fn set_of(first: i32, second: i32, third: i32): btree.SortedSet<i32> {
    var out = btree.set_new<i32>()
    out.insert(first)
    out.insert(second)
    out.insert(third)
    out
}

fn run(): i32 throws Error {
    var buffer = [0u8; 64]

    // Construction, membership and endpoints.
    var empty = btree.set_new<i32>()
    if !empty.is_empty() || empty.len() != 0usize || empty.contains(1) { return 1 }
    if empty.first().is_present() || empty.last().is_present() || empty.pop_first().is_present() { return 2 }
    var defaulted: btree.SortedSet<i32> = default_value<btree.SortedSet<i32>>()
    if !defaulted.is_empty() { return 3 }
    var set = btree.set_new<i32>()
    if !set.insert(5) || !set.insert(1) || !set.insert(9) { return 4 }
    if set.insert(5) { return 5 }
    if set.len() != 3usize || !set.contains(9) || set.contains(2) { return 6 }
    match set.get(1) {
        present(stored) => { if *stored != 1 { return 7 } },
        none => { return 8 }
    }
    if *set.first().unwrap() != 1 || *set.last().unwrap() != 9 { return 9 }

    // Replace and take return the stored element; remove reports presence.
    match set.replace(5) {
        present(old) => { if old != 5 { return 10 } },
        none => { return 11 }
    }
    match take set.`take`(1) {
        present(old) => { if old != 1 { return 12 } },
        none => { return 13 }
    }
    if set.remove(1) || !set.remove(5) || set.len() != 1usize { return 14 }
    set.insert(2)
    set.insert(7)
    set.insert(4)

    // Ordered iteration and range scans.
    var previous = -1
    var ordered = 0
    for value in set.iter() {
        if *value <= previous { return 15 }
        previous = *value
        ordered += 1
    }
    if ordered != 4 { return 16 }
    var inside = 0
    for value in set.range(2, 7) { inside += value.key }
    if inside != 2 + 4 { return 17 }
    var none_inside = 0
    for value in set.range(7, 7) { none_inside += 1 }
    if none_inside != 0 { return 18 }
    match take std.panic.catch_panic(fn(): Unit {
        let _ = set.range(7, 2)
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 18 }
    }

    // Ends and retention.
    match set.pop_last() {
        present(value) => { if value != 9 { return 19 } },
        none => { return 20 }
    }
    match set.pop_first() {
        present(value) => { if value != 2 { return 21 } },
        none => { return 22 }
    }
    set.insert(10)
    set.insert(11)
    var kept_visits = 0
    set.retain(fn(read value: i32): bool {
        kept_visits += 1
        value % 2 == 0
    })
    if kept_visits != 4 || set.len() != 2usize || !set.contains(4) || !set.contains(10) { return 23 }
    var extracted = 0
    for value in set.extract_if(fn(read value: i32): bool { value == 4 }) { extracted += value }
    if extracted != 4 || set.len() != 1usize { return 24 }
    var upper = set_of(20, 30, 40)
    var tail = upper.split_off(30)
    if upper.len() != 1usize || tail.len() != 2usize || !tail.contains(40) { return 25 }
    var source = set_of(60, 70, 80)
    tail.append(mut source)
    if !source.is_empty() || tail.len() != 5usize { return 26 }
    set.clear()
    if !set.is_empty() { return 27 }

    // Algebra: each operation yields the elements of the matching sets, in order.
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
    if !set_of(2, 3, 3).is_subset(read left) || set_of(2, 9, 3).is_subset(read left) { return 34 }
    if !left.is_superset(read set_of(1, 3, 3)) || left.is_superset(read right) { return 35 }
    if !left.is_disjoint(read set_of(9, 10, 11)) || left.is_disjoint(read right) { return 36 }

    // Clone, ordering, Debug and collection construction.
    let duplicate = left.clone()
    if duplicate != left || duplicate.len() != 3usize { return 40 }
    if left.cmp(right) != Ordering.Less || !(left < right) { return 41 }
    let written = try render(read left, mut buffer)
    match written_text(read buffer, written) {
        present(text) => { if text != "{1, 2, 3}" { return 42 } },
        none => { return 43 }
    }
    var keyed = vec.new<i32>()
    keyed.push(8)
    keyed.push(8)
    keyed.push(6)
    var built = btree.SortedSet<i32>.(FromItems<i32>).from_iter(keyed)
    if built.len() != 2usize || *built.first().unwrap() != 6 { return 44 }
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
    let same_order = set_of(1, 2, 3)
    let reordered = set_of(3, 1, 2)
    if !require_eq(read same_order) || !(same_order == reordered) ||
        hash_one(read same_order) != hash_one(read reordered) {
        return 52
    }

    // Owned iteration yields ascending elements.
    var owned_total = 0
    for value in built.into_iter() { owned_total += value }
    if owned_total != 21 { return 51 }
    return 0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 99 }
}
