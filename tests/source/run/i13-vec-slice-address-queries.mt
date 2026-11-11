// profiles: debug release
import alloc.vec.List
import core.convert.From
import std.panic.CatchResult

fn main(): i32 {
    let values = List<i32>.(From<[i32; 4]>).from([7, 7, 7, 7])
    let other = List<i32>.(From<[i32; 2]>).from([7, 7])
    assert(values.element_offset(read values[0usize]) == present(0usize),
        "first address")
    assert(values.element_offset(read values[3usize]) == present(3usize),
        "equal elements use address rather than value")
    assert(values.element_offset(read other[0usize]).is_none(),
        "foreign element is outside allocation")
    match values.subslice_range(read values[1usize..3usize]) {
        present(range) => {
            assert(range.start == 1usize && range.end == 3usize, "contained range")
        },
        none => { return 1 }
    }
    match values.subslice_range(read values[4usize..4usize]) {
        present(range) => {
            assert(range.start == 4usize && range.end == 4usize, "empty end range")
        },
        none => { return 2 }
    }
    let middle = read values[1usize..3usize]
    assert(middle.subslice_range(values.as_slice()).is_none(),
        "containing allocation is not a contained subslice")
    assert(values.subslice_range(other.as_slice()).is_none(), "foreign subslice")
    let empty = List<i32>.(From<[i32; 0]>).from([])
    match empty.subslice_range(empty.as_slice()) {
        present(range) => {
            assert(range.start == 0usize && range.end == 0usize, "empty self range")
        },
        none => { return 3 }
    }
    match take std.panic.catch_panic(take fn(): Unit {
        let zero = [()]
        let _ = zero.element_offset(read zero[0usize])
    }) {
        CatchResult.Panicked(_) => {},
        _ => { return 4 }
    }
    match take std.panic.catch_panic(take fn(): Unit {
        let zero = [()]
        let _ = zero.subslice_range(read zero[0usize..1usize])
    }) {
        CatchResult.Panicked(_) => {},
        _ => { return 5 }
    }
    0
}
