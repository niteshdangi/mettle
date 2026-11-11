// profiles: debug release
import core.borrow.ToOwned
import core.clone.Clone
import core.iter
import core.iter.Iterator

fn double(take value: i32): i32 { value * 2 }
fn even(read value: i32): bool { value % 2 == 0 }
fn below_three(read value: i32): bool { value < 3 }
fn pair(take value: i32): iter.Range<i32> { iter.range(value * 10, value * 10 + 2) }

fn main(): i32 {
    var mapped = iter.range(0, 4).map(double)
    assert(mapped.next() == present(0), "advance mapped")
    var mapped_copy = mapped.clone()
    var mapped_owned = mapped.to_owned()
    assert(mapped.next() == present(2) && mapped_copy.next() == present(2) && mapped_owned.next() == present(2), "map clones position and callable")
    var filtered = iter.range(0, 6).filter(even)
    assert(filtered.next() == present(0), "advance filtered")
    var filtered_copy = filtered.clone()
    var filtered_owned = filtered.to_owned()
    assert(filtered.next() == present(2) && filtered_copy.next() == present(2) && filtered_owned.next() == present(2), "filter clones position and predicate")
    var taken = iter.range(0, 5).take_while(below_three)
    assert(taken.next() == present(0), "advance take while")
    var taken_copy = taken.clone()
    var taken_owned = taken.to_owned()
    assert(taken.sum<i32>() == 3 && taken_copy.sum<i32>() == 3 && taken_owned.sum<i32>() == 3, "take while clones remaining predicate state")
    var skipped = iter.range(0, 5).skip_while(below_three)
    assert(skipped.next() == present(3), "advance skip while")
    var skipped_copy = skipped.clone()
    var skipped_owned = skipped.to_owned()
    assert(skipped.next() == present(4) && skipped_copy.next() == present(4) && skipped_owned.next() == present(4), "skip while clones started state")
    var flattened = iter.range(0, 3).flat_map(pair)
    assert(flattened.next() == present(0), "advance flat map")
    var flattened_copy = flattened.clone()
    var flattened_owned = flattened.to_owned()
    assert(flattened.next() == present(1) && flattened_copy.next() == present(1) && flattened_owned.next() == present(1), "flat map clones active inner")
    assert(flattened.sum<i32>() == 62 && flattened_copy.sum<i32>() == 62 && flattened_owned.sum<i32>() == 62, "flat map clones outer and callable")
    0
}
