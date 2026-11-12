// profiles: debug release
import core.ptr.NonNull

const fn shared_projection(): i32 {
    let value = 17i32
    let pointer = NonNull.from_ref(read value).cast<i32>()
    unsafe { *pointer.as_ref() }
}

const fn exclusive_projection(): i32 {
    var value = 19i32
    var pointer = NonNull.from_mut(mut value)
    unsafe { *pointer.as_mut() = 23i32 }
    let raw = pointer.as_ptr()
    unsafe { *raw }
}

const fn element_offsets(): i32 {
    var values = [5i32, 11i32, 29i32]
    let raw = core.ptr.from_mut(mut values).cast<i32>()
    let first = unsafe { NonNull.new_unchecked(raw) }
    let last = unsafe { first.add(2usize) }
    let middle = unsafe { last.sub(1usize) }
    unsafe { *middle.as_ref() }
}

const fn literal_byte(): u8 {
    let bytes: read [u8; 1] = b"Z"
    let pointer = NonNull.from_ref(read bytes[0usize])
    unsafe { *pointer.as_ref() }
}

const SHARED: i32 = shared_projection()
const EXCLUSIVE: i32 = exclusive_projection()
const MIDDLE: i32 = element_offsets()
const LITERAL: u8 = literal_byte()

fn main(): i32 {
    if SHARED != 17i32 || EXCLUSIVE != 23i32 || MIDDLE != 11i32 { return 1 }
    if LITERAL != 90u8 { return 2 }
    0
}
