// profiles: debug release
import core.array
import core.cmp.PartialEq

static mut CALLS: usize = 0usize
static mut DROPS: usize = 0usize
type Item {
    value: usize
    drop { unsafe { DROPS += 1usize } }
}

fn main(): i32 {
    let values: [Item; 3] = array.from_fn(fn(index: usize): Item {
        unsafe {
            assert(index == CALLS, "ascending construction")
            CALLS += 1usize
        }
        Item(index + 1usize)
    })
    let mapped = values.map(fn(take value: Item): usize {
        unsafe {
            assert(value.value == DROPS + 1usize, "ascending consuming map")
        }
        value.value * 2usize
    })
    if mapped != [2usize, 4usize, 6usize] { return 1 }
    if unsafe { CALLS != 3usize || DROPS != 3usize } { return 2 }
    let empty: [Item; 0] = array.from_fn(fn(index: usize): Item {
        panic("empty construction must not call its callback")
    })
    let mapped_empty = empty.map(fn(take value: Item): bool {
        panic("empty map must not call its callback")
    })
    if mapped_empty.len() != 0usize { return 3 }
    if unsafe { CALLS != 3usize || DROPS != 3usize } { return 4 }
    var counter = 0usize
    let counted: [usize; 3] = array.from_fn(fn(index: usize): usize {
        counter += 1usize
        counter + index
    })
    if counted != [1usize, 3usize, 5usize] || counter != 3usize { return 5 }
    0
}
