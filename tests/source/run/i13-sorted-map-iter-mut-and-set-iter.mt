import alloc.btree
import core.iter.{Iterator, BidirectionalIterator, Iterable}

type CountedValue {
    value: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        var map = btree.new<i32, CountedValue>()
        let _a = map.insert(7, CountedValue(70, counter))
        let _b = map.insert(1, CountedValue(10, counter))
        let _c = map.insert(4, CountedValue(40, counter))
        {
            var iter = map.iter_mut()
            match take iter.next() {
                present(pair) => {
                    assert(*pair.0 == 1, "sorted mutable front")
                    pair.1.value += 100
                },
                none => { return 1 }
            }
        }
        assert(map.len() == 3usize && drops == 0, "early iterator drop preserves entries")
        {
            var iter = map.iter_mut()
            assert(iter.size_hint() == (3usize, present(3usize)), "ordered mutable hint")
            match take iter.next() {
                present(pair) => { assert(*pair.0 == 1, "first key"); pair.1.value += 1 },
                none => { return 2 }
            }
            match take iter.next_back() {
                present(pair) => { assert(*pair.0 == 7, "last key"); pair.1.value += 1 },
                none => { return 3 }
            }
            assert(iter.size_hint() == (1usize, present(1usize)), "mixed iterator hint")
            match take iter.next() {
                present(pair) => { assert(*pair.0 == 4, "middle key"); pair.1.value += 1 },
                none => { return 4 }
            }
            assert(iter.size_hint() == (0usize, present(0usize)), "ordered iterator exhausted")
            assert(iter.next_back().is_none() && iter.next().is_none(), "no slot repeated after mixed exhaustion")
        }
        match map.get(1) {
            present(value) => assert(value.value == 111, "first mutation"),
            none => { return 5 }
        }
        match map.get(4) {
            present(value) => assert(value.value == 41, "middle mutation"),
            none => { return 6 }
        }
        match map.get(7) {
            present(value) => assert(value.value == 71, "last mutation"),
            none => { return 7 }
        }
    }
    assert(drops == 3, "ordered payloads dropped once")
    var set = btree.set_new<i32>()
    let _d = set.insert(7)
    let _e = set.insert(2)
    let _f = set.insert(5)
    let expected = [2, 5, 7]
    var index = 0usize
    for key in read set {
        assert(*key == expected[index], "sorted set yields ordered keys")
        index += 1usize
    }
    assert(index == 3usize, "sorted set visits all keys")
    var iter = set.iter()
    assert(iter.size_hint() == (3usize, present(3usize)), "sorted set hint")
    match iter.next_back() {
        present(key) => assert(*key == 7, "sorted set back key"),
        none => { return 8 }
    }
    assert(iter.size_hint() == (2usize, present(2usize)), "sorted set mixed hint")
    match iter.next() {
        present(key) => assert(*key == 2, "sorted set front key"),
        none => { return 9 }
    }
    var empty = btree.new<i32, i32>()
    var empty_iter = empty.iter_mut()
    assert(empty_iter.next().is_none() && empty_iter.next_back().is_none(), "empty ordered mutable iteration")
    0
}
