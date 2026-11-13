// profiles: debug release
import alloc.vec
import core.text
import core.text.Text

fn main(): i32 {
    var values = [1, 2, 3, 4]
    let view: mut [i32] = mut values
    for value in view.iter_mut() { *value += 10 }
    let (left, right) = view.split_at_mut(1usize)
    left[0usize] = 0
    right[0usize] = 99
    if values[0usize] != 0 || values[1usize] != 99 || values[3usize] != 14 { return 1 }

    let read_pointer = (read values).as_ptr()
    if unsafe { *read_pointer } != 0 { return 2 }
    let write_pointer = (mut values).as_mut_ptr()
    unsafe { *write_pointer = 5 }
    if values[0usize] != 5 { return 3 }

    let mixed = [72u8, 101u8, 76u8]
    let ascii: read [u8] = read mixed
    let lowered = ascii.to_ascii_lowercase()
    let raised = ascii.to_ascii_uppercase()
    if lowered.as_slice()[0usize] != 104u8 || lowered.as_slice()[2usize] != 108u8 || raised.as_slice()[1usize] != 69u8 { return 4 }

    var bytes = [97u8, 98u8, 99u8, 100u8]
    let editable: mut Text = unsafe { text.from_utf8_unchecked_mut(mut bytes) }
    let (head, tail) = editable.split_at_mut(2usize)
    if head != "ab" || tail != "cd" { return 5 }
    0
}
