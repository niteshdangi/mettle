import alloc.hash_map
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
        var map = hash_map.new<i32, CountedValue>()
        let _a = map.insert(1, CountedValue(10, counter))
        let _b = map.insert(3, CountedValue(30, counter))
        {
            var iter = map.iter()
            assert(iter.size_hint() == (2usize, present(2usize)), "exact borrowed iterator hint")
            assert(iter.next().is_present(), "borrowed entry")
            assert(iter.size_hint() == (1usize, present(1usize)), "borrowed hint after pull")
        }
        var first_key = 0
        {
            var iter = map.iter_mut()
            assert(iter.size_hint() == (2usize, present(2usize)), "mutable iterator hint")
            match take iter.next() {
                present(pair) => { first_key = *pair.0; pair.1.value += 1 },
                none => { return 1 }
            }
            assert(iter.size_hint() == (1usize, present(1usize)), "mutable hint after pull")
        }
        assert(map.len() == 2usize && drops == 0, "dropping iterator preserves entries")
        var seen = 0
        {
            var iter = map.iter_mut()
            while true {
                match take iter.next() {
                    present(pair) => {
                        pair.1.value += *pair.0 * 10
                        seen += 1
                    },
                    none => { break }
                }
            }
            assert(iter.size_hint() == (0usize, present(0usize)), "exhausted mutable hint")
            assert(iter.next().is_none(), "no mutable slot reissued")
        }
        assert(seen == 2, "each entry visited once")
        match map.get(1) {
            present(value) => assert(value.value == 20 + if first_key == 1 { 1 } else { 0 }, "first value mutation"),
            none => { return 2 }
        }
        match map.get(3) {
            present(value) => assert(value.value == 60 + if first_key == 3 { 1 } else { 0 }, "second value mutation"),
            none => { return 3 }
        }
        {
            var values = map.values_mut()
            assert(values.size_hint() == (2usize, present(2usize)), "values hint")
            assert(values.next().is_present(), "mutable value")
            assert(values.size_hint() == (1usize, present(1usize)), "values hint after pull")
        }
    }
    assert(drops == 2, "payloads dropped once")
    var set = hash_map.set_new<i32>()
    let _c = set.insert(7)
    let _d = set.insert(2)
    let _e = set.insert(5)
    var count = 0
    var total = 0
    for key in read set {
        assert(*key == 2 || *key == 5 || *key == 7, "set yields keys")
        count += 1
        total += *key
    }
    assert(count == 3 && total == 14, "set visits every key")
    var iter = set.iter()
    assert(iter.size_hint() == (3usize, present(3usize)), "set hint")
    assert(iter.next().is_present(), "set key")
    assert(iter.size_hint() == (2usize, present(2usize)), "set hint after pull")
    var map = hash_map.new<i32, i32>()
    let _f = map.insert(1, 10)
    let _g = map.insert(2, 20)
    {
        var drain = map.drain()
        assert(drain.size_hint() == (2usize, present(2usize)), "drain hint")
        assert(drain.next().is_present(), "front drain")
        assert(drain.size_hint() == (1usize, present(1usize)), "drain hint after pull")
        assert(drain.next_back().is_present(), "back drain")
        assert(drain.size_hint() == (0usize, present(0usize)), "drain exhausted")
    }
    assert(map.is_empty(), "drain removes entries")
    {
        var empty = map.iter_mut()
        assert(empty.next().is_none() && empty.size_hint() == (0usize, present(0usize)), "empty mutable iteration")
    }
    0
}
