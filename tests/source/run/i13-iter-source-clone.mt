// profiles: debug release
import alloc.linked_list
import core.borrow.AsRef
import core.clone.Clone
import core.iter
import core.iter.{Iterator, OwnedIterable}

fn main(): i32 {
    var once = iter.once(5i32)
    var once_copy = once.clone()
    if once.next() != present(5) || once_copy.next() != present(5) { return 1 }
    if once.next().is_present() || once_copy.next().is_present() { return 2 }

    var empty = iter.empty<i32>()
    var empty_copy = empty.clone()
    if empty.next().is_present() || empty_copy.next().is_present() { return 3 }

    var generated = iter.from_fn(fn(): i32? { present(8) })
    var generated_copy = generated.clone()
    if generated.next() != present(8) || generated_copy.next() != present(8) { return 4 }

    var generated_once = iter.once_with(fn(): i32 { 9 })
    var generated_once_copy = generated_once.clone()
    if generated_once.next() != present(9) || generated_once_copy.next() != present(9) { return 5 }

    var repeated_with = iter.repeat_with(fn(): i32 { 10 })
    var repeated_with_copy = repeated_with.clone()
    if repeated_with.next() != present(10) || repeated_with_copy.next() != present(10) { return 6 }

    var repeated = iter.repeat(11i32)
    var repeated_copy = repeated.clone()
    if repeated.next() != present(11) || repeated_copy.next() != present(11) { return 7 }

    var successors = iter.successors(
        present(1i32),
        fn(read value: i32): i32? { if value < 3i32 { present(value + 1i32) } else { none } }
    )
    if successors.next() != present(1) { return 8 }
    var successors_copy = successors.clone()
    if successors.next() != present(2) || successors_copy.next() != present(2) { return 9 }
    if successors.next() != present(3) || successors_copy.next() != present(3) { return 10 }
    if successors.next().is_present() || successors_copy.next().is_present() { return 31 }

    var finite = iter.repeat_n(12i32, 3usize)
    if finite.next() != present(12) { return 11 }
    var finite_copy = finite.clone()
    if finite.next() != present(12) || finite_copy.next() != present(12) { return 12 }
    if finite.next() != present(12) || finite_copy.next() != present(12) { return 13 }
    if finite.next().is_present() || finite_copy.next().is_present() { return 14 }

    var array = [1i32, 2i32, 3i32].into_iter()
    if array.next() != present(1) { return 15 }
    var array_copy = array.clone()
    if array.next_back() != present(3) || array_copy.next_back() != present(3) { return 16 }
    if array.next() != present(2) || array_copy.next() != present(2) { return 17 }
    if array.next().is_present() || array_copy.next().is_present() { return 18 }

    let values = [1i32, 2i32, 3i32]
    var slice_iter = values.iter()
    match slice_iter.next() {
        present(value) => { if *value != 1i32 { return 19 } },
        none => { return 19 }
    }
    var slice_iter_copy = slice_iter.clone()
    match (slice_iter.next(), slice_iter_copy.next()) {
        (present(left), present(right)) => { if *left != 2i32 || *right != 2i32 { return 20 } },
        _ => { return 20 }
    }
    let slice_remaining = slice_iter.as_ref()
    if slice_remaining.len() != 1usize || slice_remaining[0usize] != 3i32 { return 27 }
    var mutable_values = [4i32, 5i32, 6i32]
    var mutable_iter = mutable_values.iter_mut()
    if mutable_iter.next().is_none() { return 28 }
    let mutable_remaining = mutable_iter.as_ref()
    if mutable_remaining.len() != 2usize || mutable_remaining[0usize] != 5i32 ||
        mutable_remaining[1usize] != 6i32 {
        return 29
    }

    var split = values.split(fn(read value: i32): bool { value == 2i32 })
    if split.next().is_none() { return 21 }
    var split_copy = split.clone()
    match (split.next(), split_copy.next()) {
        (present(left), present(right)) => {
            if left.len() != 1usize || right.len() != 1usize ||
                left[0usize] != 3i32 || right[0usize] != 3i32 {
                return 22
            }
        },
        _ => { return 22 }
    }

    var list = linked_list.new<i32>()
    list.push_back(1i32)
    list.push_back(2i32)
    list.push_back(3i32)
    {
        var borrowed = list.iter()
        match borrowed.next() {
            present(value) => { if *value != 1i32 { return 23 } },
            none => { return 23 }
        }
        var borrowed_copy = borrowed.clone()
        match (borrowed.next(), borrowed_copy.next()) {
            (present(left), present(right)) => {
                if *left != 2i32 || *right != 2i32 { return 24 }
            },
            _ => { return 24 }
        }
    }
    var owned_list = list.into_iter()
    match owned_list.next() {
        present(value) => { if value != 1i32 { return 25 } },
        none => { return 25 }
    }
    var owned_list_copy = owned_list.clone()
    if owned_list.next() != present(2i32) || owned_list_copy.next() != present(2i32) {
        return 26
    }
    0
}
