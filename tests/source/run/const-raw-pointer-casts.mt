// profiles: debug release

const fn read_element(): i32 {
    var values = [3i32, 42]
    let pointer = core.ptr.from_ref(read values) as ptr<read i32>
    unsafe { *pointer.add(1usize) }
}

const fn write_element(): i32 {
    var values = [1i32, 2]
    let pointer = core.ptr.from_mut(mut values) as ptr<read i32>
    unsafe { *pointer.cast_mut().add(1usize) = 42 }
    values[1]
}

const READ: i32 = read_element()
const WRITE: i32 = write_element()

fn main(): i32 {
    if READ == 42 && WRITE == 42 { 0 } else { 1 }
}
