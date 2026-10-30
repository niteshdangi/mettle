import alloc.linked_list;
fn main(): i32 {
    var l = linked_list.new<i32>()
    l.push_back(1)
    l.push_back(2)
    l.push_front(10)
    var s = 0
    for x in read l { s += *x }
    if s != 13 { return 1 }
    0
}
