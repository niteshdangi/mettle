// profiles: debug release
import core.default.Default

fn main(): i32 {
    var value = 4i32
    let replaced = core.mem.replace(mut value, 9i32)
    if replaced != 4i32 || value != 9i32 { return 1 }

    var left = 2i32
    var right = 7i32
    core.mem.swap(mut left, mut right)
    if left != 7i32 || right != 2i32 { return 2 }

    let taken = core.mem.`take`(mut left)
    if taken != 7i32 || left != i32.(Default).default() { return 3 }

    let value = 11i32
    if core.mem.size_of<i32>() != 4usize || core.mem.size_of_val<i32>(read value) != 4usize {
        return 4
    }
    if core.mem.align_of<i32>() == 0usize { return 5 }
    core.mem.`drop`(take value)
    core.mem.forget(take 1i32)
    0
}
