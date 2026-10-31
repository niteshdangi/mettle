import alloc.vec_deque
import alloc.vec
import core.iter.{Iterator, ExactSizeIterator, BidirectionalIterator, OwnedIterable}

fn main(): i32 {
    var list = vec.new<i32>()
    list.push(1)
    list.push(2)
    list.push(3)
    {
        var list_drain = list.drain(1usize, 3usize)
        if list_drain.len() != 2usize { return 17 }
        match list_drain.next() {
            present(value) => { if value != 2 { return 18 } },
            none => { return 18 }
        }
        if list_drain.len() != 1usize { return 19 }
    }
    if list.len() != 1usize || list[0usize] != 1 { return 20 }
    var list_owned = list.into_iter()
    if list_owned.len() != 1usize { return 21 }
    match list_owned.next() {
        present(value) => { if value != 1 { return 22 } },
        none => { return 22 }
    }
    if list_owned.len() != 0usize { return 23 }

    var deque = vec_deque.new<i32>()
    deque.push_back(10)
    deque.push_back(20)
    deque.push_back(30)
    deque.push_back(40)

    {
        var iter = deque.iter()
        if iter.len() != 4usize { return 1 }
        match iter.next() {
            present(value) => { if *value != 10 { return 2 } },
            none => { return 2 }
        }
        if iter.len() != 3usize { return 3 }
    }

    {
        var iter_mut = deque.iter_mut()
        if iter_mut.len() != 4usize { return 4 }
        match iter_mut.next() {
            present(value) => { *value += 1 },
            none => { return 5 }
        }
        if iter_mut.len() != 3usize { return 6 }
    }
    if deque[0usize] != 11 { return 7 }

    {
        var drain = deque.drain(1usize, 3usize)
        if drain.len() != 2usize { return 8 }
        match drain.next_back() {
            present(value) => { if value != 30 { return 9 } },
            none => { return 9 }
        }
        if drain.len() != 1usize { return 10 }
        match drain.next() {
            present(value) => { if value != 20 { return 11 } },
            none => { return 11 }
        }
        if drain.len() != 0usize { return 12 }
    }
    if deque.len() != 2usize || deque[0usize] != 11 || deque[1usize] != 40 {
        return 13
    }

    var owned = deque.into_iter()
    if owned.len() != 2usize { return 14 }
    match owned.next() {
        present(value) => { if value != 11 { return 15 } },
        none => { return 15 }
    }
    if owned.len() != 1usize { return 16 }
    0
}
