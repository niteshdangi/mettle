// Iterator::sum/product/min/max, and StepBy exact length and reverse alignment.
import core.iter
import core.iter.BidirectionalIterator
import core.iter.ExactSizeIterator
import core.iter.Iterator

type Item {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    if take iter.range(1, 5).sum() != 10 { return 1 }
    if take iter.empty<i32>().sum() != 0 { return 2 }
    if take iter.range(1, 5).product() != 24 { return 3 }
    if take iter.empty<i32>().product() != 1 { return 4 }

    match take iter.once(3).chain(iter.once(9)).chain(iter.once(4)).max() {
        present(value) => { if value != 9 { return 5 } },
        none => { return 5 }
    }
    match take iter.once(3).chain(iter.once(1)).chain(iter.once(4)).min() {
        present(value) => { if value != 1 { return 6 } },
        none => { return 6 }
    }
    match take iter.empty<i32>().max() { present(_) => { return 7 }, none => {} }
    match take iter.empty<i32>().min() { present(_) => { return 8 }, none => {} }

    let ten = [0i32, 1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32]
    let nine = [0i32, 1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32]
    let one = [0i32]

    // 0, 3, 6, 9
    var stepped = ten.iter().copied().step_by(3usize)
    if stepped.len() != 4usize { return 10 }
    match take stepped.next_back() {
        present(value) => { if value != 9 { return 11 } },
        none => { return 11 }
    }
    if stepped.len() != 3usize { return 12 }
    match take stepped.next() {
        present(value) => { if value != 0 { return 13 } },
        none => { return 13 }
    }
    if stepped.len() != 2usize { return 14 }
    match take stepped.next_back() {
        present(value) => { if value != 6 { return 15 } },
        none => { return 15 }
    }
    match take stepped.next_back() {
        present(value) => { if value != 3 { return 16 } },
        none => { return 16 }
    }
    match take stepped.next_back() { present(_) => { return 17 }, none => {} }
    if stepped.len() != 0usize { return 18 }

    // 0, 3, 6: the trailing 7 and 8 are not stepped onto.
    var uneven = nine.iter().copied().step_by(3usize)
    if uneven.len() != 3usize { return 20 }
    match take uneven.next_back() {
        present(value) => { if value != 6 { return 21 } },
        none => { return 21 }
    }
    if take ten.iter().copied().step_by(3usize).rev().sum() != 18 { return 22 }
    match take one.iter().copied().skip(1usize).step_by(2usize).next_back() { present(_) => { return 23 }, none => {} }
    if one.iter().copied().step_by(5usize).len() != 1usize { return 24 }

    // After the first element the grid shifts: 3, 6, 9.
    var shifted = ten.iter().copied().step_by(3usize)
    match take shifted.next() { present(_) => {}, none => { return 30 } }
    if shifted.len() != 3usize { return 31 }
    match take shifted.next_back() {
        present(value) => { if value != 9 { return 32 } },
        none => { return 32 }
    }
    match take shifted.next_back() {
        present(value) => { if value != 6 { return 33 } },
        none => { return 33 }
    }
    match take shifted.next_back() {
        present(value) => { if value != 3 { return 34 } },
        none => { return 34 }
    }

    // Skipped items are dropped as the stride passes over them.
    var drops = 0
    {
        let counter = core.ptr.from_mut(drops)
        var pairs = iter.once(Item(counter, 1))
            .chain(iter.once(Item(counter, 2)))
            .chain(iter.once(Item(counter, 3)))
            .chain(iter.once(Item(counter, 4)))
            .chain(iter.once(Item(counter, 5)))
            .step_by(2usize)
        match take pairs.next() {
            present(item) => { if item.value != 1 { return 40 } },
            none => { return 40 }
        }
        if drops != 1 { return 41 }
        match take pairs.next() {
            present(item) => { if item.value != 3 { return 42 } },
            none => { return 42 }
        }
        if drops != 3 { return 43 }
    }
    if drops != 5 { return 44 }
    0
}
