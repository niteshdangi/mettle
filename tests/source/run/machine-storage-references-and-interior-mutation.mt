
fn expose(read value: core.mem.MaybeUninit<i32>): read i32 from value {
    unsafe { value.assume_init_ref() }
}
fn main() {
    let zero = core.mem.MaybeUninit<i64>.zeroed()
    let scalar = unsafe { zero.assume_init() }
    let storage = core.mem.MaybeUninit.new(42)
    let reference = expose(storage)
    let cell = core.cell.UnsafeCell.new(40i32)
    let pointer = cell.get()
    unsafe { pointer.write(42) }
    let inner = unsafe { cell.get_ref() }
    if scalar == 0i64 && *reference == 42 && *inner == 42 { 0 } else { 1 }
}
