// expect-exit: trap
import alloc.linked_list

fn main(): i32 {
    var list = linked_list.new<i32>()
    list.push_back(1)
    let rest = list.split_off(2usize)
    0
}
