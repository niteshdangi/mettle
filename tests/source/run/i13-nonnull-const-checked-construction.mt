// profiles: debug release
import core.ptr.NonNull

const fn null_is_absent(): bool {
    match NonNull.new(core.ptr.null_mut<i32>()) {
        none => true,
        present(_) => false
    }
}

const fn initialized_is_present(): i32 {
    let value = 17i32
    let raw = core.ptr.from_ref(read value).cast_mut()
    match NonNull.new(raw) {
        none => -1i32,
        present(pointer) => unsafe { *pointer.as_ref() }
    }
}

const fn wide_is_present(): i32 {
    let values = [5i32, 11i32]
    let view: read [i32] = read values
    let raw = core.ptr.from_ref(view).cast_mut()
    match NonNull.new(raw) {
        none => -1i32,
        present(pointer) => unsafe { pointer.as_ref()[1usize] }
    }
}

const NULL_ABSENT: bool = null_is_absent()
const INITIALIZED: i32 = initialized_is_present()
const ARRAY: i32 = wide_is_present()

fn main(): i32 {
    if !NULL_ABSENT || INITIALIZED != 17i32 || ARRAY != 11i32 { return 1 }
    0
}
