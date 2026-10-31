import core.iter.ExactSizeIterator
import core.num.{FromText, IntErrorKind}
import alloc.string
import alloc.vec

fn main(): i32 {
    var values = [1, 2, 3]
    var iter = values.iter()
    match iter.next() {
        present(item) => { if item != 1 { return 1 } },
        none => { return 2 }
    }
    if iter.len() != 2usize || iter.as_slice().len() != 2usize || iter.as_slice()[0usize] != 2 { return 3 }
    var writable = [4, 5]
    var cursor = writable.iter_mut()
    if cursor.len() != 2usize || cursor.as_slice()[1usize] != 5 { return 4 }

    match capture "42".parse<i32>() {
        success(value) => { if value != 42 { return 5 } },
        failure(_) => { return 6 }
    }
    match capture i32.(FromText).from_text("7") {
        success(value) => { if value != 7 { return 7 } },
        failure(_) => { return 8 }
    }
    match capture "nope".parse<i32>() {
        success(_) => { return 9 },
        failure(error) => { if error.kind != IntErrorKind.InvalidDigit { return 10 } }
    }

    var owned = string.from_text("ab")
    if unsafe { *owned.as_ptr() } != 97u8 { return 11 }
    unsafe { *owned.as_mut_ptr() = 99u8 }
    if owned.as_bytes()[0usize] != 99u8 { return 12 }
    var bytes = vec.new<u8>()
    bytes.push(104u8)
    bytes.push(105u8)
    let decoded = unsafe { string.from_utf8_unchecked(bytes) }
    if decoded.len() != 2usize || decoded.as_bytes()[0usize] != 104u8 { return 13 }
    0
}
