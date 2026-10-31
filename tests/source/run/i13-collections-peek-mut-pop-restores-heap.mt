// A PeekMut guard that pops leaves a valid heap, and an untouched guard keeps
// the heap ordered after the top is lowered.
import alloc.binary_heap

fn main(): i32 {
    var heap = binary_heap.new<i32>()
    heap.push(2)
    heap.push(8)
    heap.push(5)
    {
        match heap.peek_mut() {
            present(guard) => { *guard = 1 },
            none => { return 1 }
        }
    }
    match heap.peek() { present(v) => { if *v != 5 { return 2 } }, none => { return 2 } }
    match heap.pop() { present(v) => { if v != 5 { return 3 } }, none => { return 3 } }
    match heap.pop() { present(v) => { if v != 2 { return 4 } }, none => { return 4 } }
    match heap.pop() { present(v) => { if v != 1 { return 5 } }, none => { return 5 } }
    if heap.peek_mut().is_present() { return 6 }
    0
}
