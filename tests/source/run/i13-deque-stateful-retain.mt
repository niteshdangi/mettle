import alloc.vec_deque

type Marker { drop {} }

fn main(): i32 {
    var deque = vec_deque.new<i32>()
    deque.reserve(8usize)
    let capacity = deque.capacity()
    var i = 0
    while i < 8 {
        deque.push_back(i + 0)
        i += 1
    }
    i = 0
    while i < 6 {
        if deque.pop_front().or_panic() != i + 0 { return 1 }
        i += 1
    }
    i = 8
    while i < 12 {
        deque.push_back(i + 0)
        i += 1
    }
    if deque.len() != 6usize || deque[0usize] != 6 ||
        deque[5usize] != 11 { return 2 }

    var seen = 0
    deque.retain(fn(read value: i32): bool {
        seen += 1
        seen % 2 == 0
    })
    if seen != 6 || deque.len() != 3usize ||
        deque[0usize] != 7 || deque[1usize] != 9 || deque[2usize] != 11 {
        return 3
    }
    if deque.capacity() != capacity { return 4 }

    var mutated = 0
    deque.retain_mut(fn(mut value: i32): bool {
        mutated += 1
        value += mutated
        mutated != 2
    })
    if mutated != 3 || deque.len() != 2usize ||
        deque[0usize] != 8 || deque[1usize] != 14 { return 5 }
    if deque.capacity() != capacity { return 6 }

    deque.retain(fn(read value: i32): bool { true })
    if deque.len() != 2usize || deque[0usize] != 8 ||
        deque[1usize] != 14 { return 7 }
    deque.retain_mut(fn(mut value: i32): bool { false })
    if !deque.is_empty() || deque.capacity() != capacity { return 8 }

    var empty = vec_deque.new<i32>()
    var empty_calls = 0
    empty.retain(fn(read value: i32): bool {
        empty_calls += 1
        true
    })
    empty.retain_mut(fn(mut value: i32): bool {
        empty_calls += 1
        true
    })
    if empty_calls != 0 || !empty.is_empty() { return 9 }

    var markers = vec_deque.new<Marker>()
    markers.push_back(Marker())
    markers.push_back(Marker())
    markers.push_back(Marker())
    markers.push_back(Marker())
    let marker_capacity = markers.capacity()
    var marker_calls = 0
    markers.retain(fn(read value: Marker): bool {
        marker_calls += 1
        marker_calls % 2 == 0
    })
    if marker_calls != 4 || markers.len() != 2usize ||
        markers.capacity() != marker_capacity { return 10 }
    marker_calls = 0
    markers.retain_mut(fn(mut value: Marker): bool {
        marker_calls += 1
        false
    })
    if marker_calls != 2 || !markers.is_empty() ||
        markers.capacity() != marker_capacity { return 11 }
    0
}
