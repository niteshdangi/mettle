import alloc.vec
import core.iter.ExtendItems

fn main(): i32 {
    var values = vec.new<i32>()
    values.reserve_exact(4usize)
    if values.capacity() < 4usize { return 1 }
    values.push(10)
    values.push(20)
    values.push(30)
    values.insert(1usize, 15)
    if values.remove(2usize) != 20 { return 2 }
    values.retain(fn(read value: i32): bool { value >= 15 })
    values.truncate(2usize)

    var suffix = vec.new<i32>()
    suffix.push(40)
    suffix.push(50)
    values.extend(take suffix)

    var total = 0
    for value in take values { total += value }
    if total == 135 { 0 } else { 3 }
}
