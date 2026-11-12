// profiles: debug release
import core.ptr

const fn copy_values(): bool {
    let source = [7i32, 19i32]
    var destination = [0i32, 0i32]
    let from = core.ptr.from_ref(read source).cast<i32>()
    let to = core.ptr.from_mut(mut destination).cast<i32>()
    unsafe { core.ptr.copy_nonoverlapping(from, to, 2usize) }
    source[0usize] == 7i32 && source[1usize] == 19i32 &&
        destination[0usize] == 7i32 && destination[1usize] == 19i32
}

const COPIED: bool = copy_values()

fn main(): i32 { if COPIED { 0 } else { 1 } }
