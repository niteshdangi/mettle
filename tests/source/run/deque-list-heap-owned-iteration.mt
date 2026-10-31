import alloc.vec_deque
import alloc.linked_list
import alloc.binary_heap

fn main(): i32 {
    var deque = vec_deque.new<i32>()
    deque.push_back(1)
    deque.push_back(2)
    deque.push_back(3)
    match deque.pop_front() {
        present(value) => { if value != 1 { return 1 } },
        none => { return 2 }
    }
    deque.push_back(4)
    deque.push_back(5)
    deque.push_back(6)
    if deque[0usize] != 2 || deque[4usize] != 6 { return 3 }
    var deque_sum = 0i32
    for value in take deque { deque_sum += value }
    if deque_sum != 20i32 { return 4 }

    var list = linked_list.new<i32>()
    list.push_front(2)
    list.push_front(1)
    list.push_back(3)
    var list_sum = 0i32
    for value in read list { list_sum += *value }
    if list_sum != 6i32 { return 5 }
    match list.pop_back() {
        present(value) => { if value != 3 { return 6 } },
        none => { return 7 }
    }
    list_sum = 0i32
    for value in take list { list_sum += value }
    if list_sum != 3i32 { return 8 }

    var queue = binary_heap.new<i32>()
    queue.push(2)
    queue.push(9)
    queue.push(4)
    match queue.pop() {
        present(value) => { if value != 9 { return 9 } },
        none => { return 10 }
    }
    var heap_sum = 0i32
    for value in take queue { heap_sum += value }
    if heap_sum != 6i32 { return 11 }
    0
}
