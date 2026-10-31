// Mutable collection retain predicates may keep state between elements.
import alloc.vec
import alloc.vec_deque

fn main(): i32 {
    var list = vec.new<i32>()
    list.push(1)
    list.push(2)
    list.push(3)
    var list_calls = 0
    list.retain_mut(fn(value: mut i32): bool {
        list_calls += 1
        *value += list_calls
        list_calls != 2
    })
    if list_calls != 3 || list.len() != 2usize || list[0usize] != 2 ||
       list[1usize] != 6 { return 1 }

    var deque = vec_deque.new<i32>()
    deque.push_back(1)
    deque.push_back(2)
    deque.push_back(3)
    var deque_calls = 0
    deque.retain_mut(fn(value: mut i32): bool {
        deque_calls += 1
        *value += deque_calls
        deque_calls != 2
    })
    if deque_calls != 3 || deque.len() != 2usize || deque[0usize] != 2 ||
       deque[1usize] != 6 { return 2 }
    0
}
