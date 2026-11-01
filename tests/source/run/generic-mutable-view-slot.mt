fn replace<T>(slot: mut T, value: take T): Unit {
    slot = value
}

fn forward<T>(value: take T, replacement: take T): T {
    var slot = value
    replace(mut slot, replacement)
    slot
}

fn main(): i32 {
    let first = "first"
    let second = "second"
    let text = forward(first, second)
    assert(text == second, "generic mutable borrow replaces a fat view slot")
    let left = [1u8, 2u8]
    let right = [3u8, 4u8, 5u8]
    let first_slice = read left[0usize..2usize]
    let second_slice = read right[0usize..3usize]
    let slice = forward(first_slice, second_slice)
    assert(slice.len() == 3usize && slice[2usize] == 5u8, "slice metadata follows replacement")
    0
}
