fn main(): i32 {
    let values: heap [i32] = heap [10, 20, 30]
    let view = values.get()
    if view.len() != 3usize || view[2] != 30 { return 1 }
    if core.mem.size_of_val(view) != 12usize ||
       core.mem.align_of_val(view) != core.mem.align_of<i32>() { return 2 }
    0
}
