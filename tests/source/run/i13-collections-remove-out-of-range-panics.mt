// expect-exit: trap
import alloc.linked_list

fn main(): i32 {
    var list = linked_list.new<i32>()
    list.push_back(1)
    let gone = list.remove(1usize)
    0
}
