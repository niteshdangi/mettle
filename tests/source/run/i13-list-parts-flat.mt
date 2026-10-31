import alloc.vec

fn main(): i32 {
    var values = vec.new<i32>()
    {
        let slot = values.push_mut(4)
        *slot = 9
    }
    if values.len() != 1usize || values[0usize] != 9 { return 1 }
    let parts = values.into_parts()
    var restored = unsafe { vec.from_parts(parts.0, parts.1, parts.2) }
    if restored.len() != 1usize || restored[0usize] != 9 { return 2 }
    let tail = restored.split_off_mut(1usize)
    if restored.len() != 1usize || tail.len() != 0usize { return 3 }
    var rows = vec.new<[i32; 2]>()
    rows.push([1, 2])
    rows.push([3, 4])
    let flat = rows.into_flattened()
    if flat.len() != 4usize || flat[0usize] != 1 || flat[3usize] != 4 { return 4 }
    var folded = vec.new<i32>()
    folded.push(1)
    folded.push(2)
    folded.push(3)
    match folded.into_iter().try_rfold(0, fn(acc: i32, item: i32): (i32 throws i32) {
        success(acc * 10 + item)
    }) {
        success(value) => { if value != 321 { return 5 } },
        failure(_) => { return 6 }
    }
    0
}
