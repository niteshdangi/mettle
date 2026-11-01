import alloc.binary_heap
import alloc.linked_list
import alloc.vec
import alloc.vec_deque
import core.cmp.{ Eq, Ord, Ordering, PartialEq, PartialOrd }

static mut ZERO_DROPS: usize = 0usize

type ZeroDrop {
    drop { unsafe { ZERO_DROPS += 1usize } }
}

type HeapValue {
    key: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

extend HeapValue implements PartialEq {
    fn eq(other: read HeapValue): bool { self.key == other.key }
}
extend HeapValue implements Eq {}
extend HeapValue implements PartialOrd {
    fn partial_cmp(other: read HeapValue): Ordering? {
        present(self.key.cmp(other.key))
    }
}
extend HeapValue implements Ord {
    fn cmp(other: read HeapValue): Ordering { self.key.cmp(other.key) }
}

fn main(): i32 {
    {
        var zero_sized = vec.new<ZeroDrop>()
        zero_sized.push(ZeroDrop())
        zero_sized.push(ZeroDrop())
        zero_sized.push(ZeroDrop())
        zero_sized.dedup_by(fn(current: mut ZeroDrop, previous: mut ZeroDrop): bool {
            true
        })
        assert(zero_sized.len() == 1usize, "zero-sized dedup length")
        unsafe { assert(ZERO_DROPS == 2usize, "zero-sized duplicates drop once") }
    }
    unsafe { assert(ZERO_DROPS == 3usize, "zero-sized survivor drops once") }

    var values = vec.new<i32>()
    values.push(1)
    values.push(1)
    values.push(2)
    values.push(2)
    values.push(3)
    var comparisons = 0
    values.dedup_by(fn(current: mut i32, previous: mut i32): bool {
        comparisons += 1
        current == previous
    })
    assert(comparisons == 4, "dedup callback visits adjacent pairs once")
    assert(values.len() == 3usize && values[0usize] == 1 &&
        values[1usize] == 2 && values[2usize] == 3, "dedup keeps first item")
    var key_calls = 0
    values.dedup_by_key(fn(value: mut i32): i32 {
        key_calls += 1
        value
    })
    assert(key_calls == 4 && values.len() == 3usize,
        "dedup key callback is stateful")

    var generated = 0
    values.resize_with(5usize, fn(): i32 {
        generated += 1
        generated + 10
    })
    assert(generated == 2 && values[3usize] == 11 &&
        values[4usize] == 12, "resize generator state")
    var pop_calls = 0
    match values.pop_if(fn(value: mut i32): bool {
        pop_calls += 1
        value == 12
    }) {
        present(value) => assert(value == 12, "vector conditional pop"),
        none => { return 7 }
    }
    assert(pop_calls == 1, "vector conditional pop is called once")

    var extraction_source = vec.new<i32>()
    extraction_source.push(1)
    extraction_source.push(2)
    extraction_source.push(3)
    extraction_source.push(4)
    var extraction_calls = 0
    {
        var extracted = extraction_source.extract_if(
            0usize..extraction_source.len(),
            fn(value: mut i32): bool {
                extraction_calls += 1
                value % 2 == 0
            }
        )
        match take extracted.next() {
            present(value) => assert(value == 2, "stateful vector extraction"),
            none => { return 8 }
        }
    }
    assert(extraction_calls == 2 && extraction_source.len() == 3usize &&
        extraction_source[0usize] == 1 && extraction_source[1usize] == 3 &&
        extraction_source[2usize] == 4, "dropping extraction preserves suffix")

    var deque = vec_deque.new<i32>()
    deque.push_back(1)
    deque.push_back(2)
    deque.push_back(2)
    deque.push_back(4)
    var searches = 0
    match capture deque.binary_search_by(fn(value: read i32): Ordering {
        searches += 1
        value.cmp(2)
    }) {
        success(index) => assert(index == 1usize || index == 2usize, "deque search result"),
        failure(_) => { return 1 }
    }
    assert(searches > 0, "deque search invokes stateful comparator")
    searches = 0
    let deque_key = 4
    match capture deque.binary_search_by_key(read deque_key, fn(value: read i32): i32 {
        searches += 1
        value
    }) {
        success(index) => assert(index == 3usize, "deque key search result"),
        failure(_) => { return 2 }
    }
    assert(searches > 0, "deque key projection is stateful")
    match capture deque.binary_search(4) {
        success(index) => assert(index == 3usize, "deque ordered search"),
        failure(_) => { return 6 }
    }
    searches = 0
    assert(deque.partition_point(fn(value: read i32): bool {
        searches += 1
        value < 3
    }) == 3usize, "deque partition point")
    assert(searches == 2, "deque partition predicate state")

    var pop_calls = 0
    match deque.pop_front_if(fn(value: mut i32): bool {
        pop_calls += 1
        value == 1
    }) {
        present(value) => assert(value == 1, "deque conditional pop"),
        none => { return 3 }
    }
    assert(pop_calls == 1, "conditional pop calls once")
    var deque_generated = 0
    deque.resize_with(5usize, fn(): i32 {
        deque_generated += 1
        deque_generated + 10
    })
    assert(deque_generated == 2 && deque[3usize] == 11 &&
        deque[4usize] == 12, "deque generator state")
    pop_calls = 0
    match deque.pop_back_if(fn(value: mut i32): bool {
        pop_calls += 1
        value == 12
    }) {
        present(value) => assert(value == 12, "deque conditional back pop"),
        none => { return 9 }
    }
    assert(pop_calls == 1, "conditional back pop calls once")

    var linked = linked_list.new<i32>()
    linked.push_back(1)
    linked.push_back(2)
    linked.push_back(3)
    linked.push_back(4)
    linked.push_back(5)
    var visits = 0
    {
        var extracted = linked.extract_if(fn(value: mut i32): bool {
            visits += 1
            value % 2 == 0
        })
        match take extracted.next() {
            present(value) => assert(value == 2, "linked extraction order"),
            none => { return 4 }
        }
    }
    assert(visits == 2, "linked extraction stops at first yielded item")
    assert(linked.len() == 4usize, "dropping extraction keeps unvisited nodes")
    var remaining = linked.extract_if(fn(value: mut i32): bool {
        visits += 1
        value == 4
    })
    match take remaining.next() {
        present(value) => assert(value == 4, "linked extraction continues"),
        none => { return 5 }
    }
    assert(remaining.next().is_none(), "linked extraction completes")
    assert(linked.len() == 3usize && *linked.front().unwrap() == 1 &&
        *linked.back().unwrap() == 5, "linked list stays linked after extraction")

    var drops = 0
    {
        var queue = binary_heap.new<HeapValue>()
        let counter = core.ptr.from_mut(drops)
        queue.push(HeapValue(1, counter))
        queue.push(HeapValue(2, counter))
        queue.push(HeapValue(3, counter))
        queue.push(HeapValue(4, counter))
        queue.push(HeapValue(5, counter))
        queue.push(HeapValue(6, counter))
        var heap_visits = 0
        queue.retain(fn(value: read HeapValue): bool {
            heap_visits += 1
            value.key % 2 == 0
        })
        assert(heap_visits == 6 && queue.len() == 3usize, "heap retain visits once")
        unsafe { assert(drops == 3, "heap retain drops rejected values") }
        var previous = 7
        while true {
            match take queue.pop() {
                present(value) => {
                    assert(value.key < previous, "heap order after retain")
                    previous = value.key
                },
                none => { break }
            }
        }
    }
    unsafe { assert(drops == 6, "retained heap values drop once") }

    var adversarial_drops = 0
    {
        var queue = binary_heap.new<HeapValue>()
        let counter = core.ptr.from_mut(adversarial_drops)
        queue.push(HeapValue(100, counter))
        queue.push(HeapValue(5, counter))
        queue.push(HeapValue(90, counter))
        queue.push(HeapValue(4, counter))
        queue.push(HeapValue(3, counter))
        queue.push(HeapValue(80, counter))
        queue.push(HeapValue(85, counter))
        var visits = [0usize; 7usize]
        queue.retain(fn(value: read HeapValue): bool {
            if value.key == 100 { visits[0usize] += 1usize }
            else if value.key == 5 { visits[1usize] += 1usize }
            else if value.key == 90 { visits[2usize] += 1usize }
            else if value.key == 4 { visits[3usize] += 1usize }
            else if value.key == 3 { visits[4usize] += 1usize }
            else if value.key == 80 { visits[5usize] += 1usize }
            else if value.key == 85 { visits[6usize] += 1usize }
            value.key != 4 && value.key != 85
        })
        assert(visits[0usize] == 1usize && visits[1usize] == 1usize &&
            visits[2usize] == 1usize && visits[3usize] == 1usize &&
            visits[4usize] == 1usize && visits[5usize] == 1usize &&
            visits[6usize] == 1usize, "heap retain visits every original key once")
        assert(queue.len() == 5usize, "heap retain removes only rejected keys")
        unsafe {
            assert(adversarial_drops == 2, "heap retain drops rejected keys once")
        }
        let expected = [100, 90, 80, 5, 3]
        var index = 0usize
        while index < 5usize {
            let value = match take queue.pop() {
                present(item) => item,
                none => { return 10 }
            }
            assert(value.key == expected[index], "heap retain preserves pop order")
            index += 1usize
        }
    }
    unsafe {
        assert(adversarial_drops == 7, "heap retain owns and drops every original key once")
    }
    0
}
