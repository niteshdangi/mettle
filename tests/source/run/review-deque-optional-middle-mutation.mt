// profiles: debug release
fn main(): i32 {
    var values = alloc.vec_deque.new<i32>()
    if values.remove(0usize).is_present() || values.swap_remove_front(0usize).is_present() ||
        values.swap_remove_back(0usize).is_present() { return 1 }
    var head = 0usize
    while head < 8usize {
        var at = 0usize
        while at <= 6usize {
            values.clear()
            values.reserve_exact(8usize)
            var index = 0usize
            while index < 8usize { values.push_back(index as i32); index += 1usize }
            index = 0usize
            while index < head {
                let removed = values.pop_front()
                values.push_back((8usize + index) as i32)
                index += 1usize
            }
            values.truncate(6usize)
            values.insert(at, 99)
            if values.len() != 7usize || values.remove(at).or_panic() != 99 { return 2 }
            index = 0usize
            while index < 6usize {
                if values[index] != (head + index) as i32 { return 3 }
                index += 1usize
            }
            if values.remove(6usize).is_present() || values.swap_remove_front(6usize).is_present() ||
                values.swap_remove_back(6usize).is_present() { return 4 }
            values.rotate_left(5usize)
            if values[0usize] != (head + 5usize) as i32 { return 5 }
            values.rotate_right(5usize)
            if values[0usize] != head as i32 { return 6 }
            at += 1usize
        }
        head += 1usize
    }
    if values.swap_remove_front(2usize).is_none() || values.swap_remove_back(2usize).is_none() { return 7 }
    0
}
