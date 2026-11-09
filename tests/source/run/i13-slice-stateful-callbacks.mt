import alloc.vec
import core.cmp.{ Ordering, PartialEq, PartialOrd }
import core.iter.{ Iterator, BidirectionalIterator }

type PartialKey {
    value: i32
    incomparable: bool
}

extend PartialKey implements PartialEq {
    fn eq(read other: PartialKey): bool {
        self.value == other.value && self.incomparable == other.incomparable
    }
}
extend PartialKey implements PartialOrd {
    fn partial_cmp(read other: PartialKey): Ordering? {
        if self.incomparable || other.incomparable {
            none
        } else {
            present(self.value.cmp(other.value))
        }
    }
}

fn main(): i32 {
    var values = [1, 2, 2, 3, 5, 8]
    let slice = read values
    var calls = 0
    match capture slice.binary_search_by(fn(read value: i32): Ordering {
        calls += 1
        value.cmp(5)
    }) {
        success(index) => assert(index == 4usize, "stateful slice search"),
        failure(_) => { return 1 }
    }
    assert(calls > 0, "slice comparator state")

    calls = 0
    let search_key = 3
    match capture slice.binary_search_by_key(read search_key, fn(read value: i32): i32 {
        calls += 1
        value
    }) {
        success(index) => assert(index == 3usize, "stateful key search"),
        failure(_) => { return 2 }
    }
    assert(calls > 0, "slice projection state")

    calls = 0
    assert(slice.partition_point(fn(read value: i32): bool {
        calls += 1
        value < 3
    }) == 3usize, "stateful partition point")
    assert(calls == 3, "partition predicate call count")

    calls = 0
    assert(slice.is_sorted_by(fn(read left: i32, read right: i32): bool {
        calls += 1
        left <= right
    }), "is_sorted_by uses a non-strict predicate")
    assert(calls == 5, "sorted comparator called for adjacent pairs")
    calls = 0
    assert(!slice.is_sorted_by(fn(read left: i32, read right: i32): bool {
        calls += 1
        left < right
    }), "strict predicate rejects duplicate neighbors")
    assert(calls == 2, "sorted check stops at first false pair")

    calls = 0
    assert(slice.is_sorted_by_key(fn(read value: i32): i32 {
        calls += 1
        value
    }), "stateful sorted key")
    assert(calls == 10, "key projection runs for each adjacent pair")
    calls = 0
    assert(!slice.is_sorted_by_key(fn(read value: i32): PartialKey {
        calls += 1
        PartialKey(value, value == 2)
    }), "incomparable keys are not sorted")
    assert(calls == 2, "partial-order key stops at incomparable pair")

    var unstable = [4, 1, 3, 2]
    calls = 0
    {
        let mutable = mut unstable
        mutable.sort_unstable_by(fn(read left: i32, read right: i32): Ordering {
            calls += 1
            left.cmp(right)
        })
    }
    assert(calls > 0 && unstable[0usize] == 1 && unstable[3usize] == 4,
        "stateful unstable comparator")

    var unstable_keys = [7, 2, 5, 1]
    calls = 0
    {
        let mutable = mut unstable_keys
        mutable.sort_unstable_by_key(fn(read value: i32): i32 {
            calls += 1
            value
        })
    }
    assert(calls > 0 && unstable_keys[0usize] == 1 &&
        unstable_keys[3usize] == 7, "stateful unstable key")

    var selected = [8, 2, 6, 4, 0]
    calls = 0
    {
        let mutable = mut selected
        let parts = take mutable.select_nth_unstable_by(
            2usize,
            fn(read left: i32, read right: i32): Ordering {
                calls += 1
                left.cmp(right)
            }
        )
        assert(*parts.1 == 4 && parts.0.len() == 2usize &&
            parts.2.len() == 2usize, "stateful selection comparator")
    }
    assert(calls > 0, "selection comparator state")

    var selected_keys = [8, 2, 6, 4, 0]
    calls = 0
    {
        let mutable = mut selected_keys
        let parts = take mutable.select_nth_unstable_by_key(
            3usize,
            fn(read value: i32): i32 {
                calls += 1
                value
            }
        )
        assert(*parts.1 == 6, "stateful selection key")
    }
    assert(calls > 0, "selection key state")

    var stable = vec.new<i32>()
    stable.push(3)
    stable.push(1)
    stable.push(2)
    calls = 0
    stable.sort_by(fn(read left: i32, read right: i32): Ordering {
        calls += 1
        left.cmp(right)
    })
    assert(calls > 0 && stable[0usize] == 1 && stable[2usize] == 3,
        "stateful stable sort")

    var cached = vec.new<i32>()
    cached.push(3)
    cached.push(1)
    cached.push(2)
    calls = 0
    cached.sort_by_cached_key(fn(read value: i32): i32 {
        calls += 1
        value
    })
    assert(calls == 3 && cached[0usize] == 1 && cached[2usize] == 3,
        "cached key is computed once per item")
    var stable_keys = vec.new<i32>()
    stable_keys.push(3)
    stable_keys.push(1)
    stable_keys.push(2)
    calls = 0
    stable_keys.sort_by_key(fn(read value: i32): i32 {
        calls += 1
        value
    })
    assert(calls > 0 && stable_keys[0usize] == 1 && stable_keys[2usize] == 3,
        "stateful stable key sort")

    calls = 0
    {
        var pieces = slice.split(fn(read value: i32): bool {
            calls += 1
            value == 2
        })
        match take pieces.next() {
            present(part) => assert(part.len() == 1usize && part[0usize] == 1,
                "stateful forward split"),
            none => { return 3 }
        }
        match take pieces.next_back() {
            present(part) => assert(part.len() == 3usize && part[0usize] == 3,
                "stateful reverse split"),
            none => { return 4 }
        }
    }
    assert(calls > 0, "split callback state is shared across directions")

    calls = 0
    {
        var chunks = slice.chunk_by(fn(read left: i32, read right: i32): bool {
            calls += 1
            left == right
        })
        match take chunks.next() {
            present(part) => assert(part.len() == 1usize && part[0usize] == 1,
                "stateful forward chunk"),
            none => { return 5 }
        }
        match take chunks.next_back() {
            present(part) => assert(part.len() == 1usize && part[0usize] == 8,
                "stateful reverse chunk"),
            none => { return 6 }
        }
    }
    assert(calls > 0, "chunk callback state is shared across directions")

    calls = 0
    {
        var limited = slice.splitn(2usize, fn(read value: i32): bool {
            calls += 1
            value == 2
        })
        match take limited.next() {
            present(part) => assert(part.len() == 1usize, "limited split first part"),
            none => { return 9 }
        }
        match take limited.next() {
            present(part) => assert(part.len() == 4usize &&
                part[0usize] == 2 && part[1usize] == 3 &&
                part[2usize] == 5 && part[3usize] == 8,
                "limited split remainder"),
            none => { return 10 }
        }
    }
    assert(calls == 2, "splitn retains callback state")

    calls = 0
    {
        var reversed = slice.rsplitn(2usize, fn(read value: i32): bool {
            calls += 1
            value == 2
        })
        match take reversed.next() {
            present(part) => assert(part.len() == 3usize && part[0usize] == 3,
                "reverse limited split first part"),
            none => { return 13 }
        }
        match take reversed.next() {
            present(part) => assert(part.len() == 2usize && part[0usize] == 1,
                "reverse limited split remainder"),
            none => { return 14 }
        }
    }
    assert(calls > 0, "rsplitn retains callback state")

    calls = 0
    {
        var inclusive = slice.split_inclusive(fn(read value: i32): bool {
            calls += 1
            value == 2
        })
        match take inclusive.next() {
            present(part) => assert(part.len() == 2usize && part[1usize] == 2,
                "inclusive split keeps separator"),
            none => { return 11 }
        }
    }
    assert(calls > 0, "inclusive split callback state")

    var split_values = [1, 0, 2, 0, 3]
    calls = 0
    {
        let mutable = mut split_values
        var pieces = mutable.split_mut(fn(read value: i32): bool {
            calls += 1
            value == 0
        })
        match take pieces.next() {
            present(part) => { part[0usize] = 9 },
            none => { return 7 }
        }
    }
    assert(split_values[0usize] == 9 && calls == 2,
        "stateful mutable split predicate")

    var inclusive_values = [1, 0, 2]
    calls = 0
    {
        let mutable = mut inclusive_values
        var pieces = mutable.split_inclusive_mut(fn(read value: i32): bool {
            calls += 1
            value == 0
        })
        match take pieces.next() {
            present(part) => { part[1usize] = 9 },
            none => { return 12 }
        }
    }
    assert(inclusive_values[1usize] == 9 && calls == 2,
        "stateful inclusive mutable split")

    var chunk_values = [1, 1, 2, 2]
    calls = 0
    {
        let mutable = mut chunk_values
        var chunks = mutable.chunk_by_mut(
            fn(read left: i32, read right: i32): bool {
                calls += 1
                left == right
            }
        )
        match take chunks.next() {
            present(part) => { part[0usize] = 7 },
            none => { return 8 }
        }
    }
    assert(chunk_values[0usize] == 7 && calls > 0,
        "stateful mutable chunk predicate")

    var filled = [0, 0, 0, 0]
    calls = 0
    {
        let mutable = mut filled
        mutable.fill_with(fn(): i32 {
            calls += 1
            calls
        })
    }
    assert(calls == 4 && filled[0usize] == 1 && filled[3usize] == 4,
        "stateful fill generator")
    0
}
