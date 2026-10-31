import alloc.vec
import core.cmp.{PartialEq, Eq, PartialOrd, Ord, Ordering}

type Item {
    key: i32
    serial: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}
copy type Pair { key: i32; serial: i32 }

extend Item implements PartialEq {
    fn eq(other: read Item): bool { self.key == other.key }
}
extend Item implements Eq {}
extend Item implements PartialOrd {
    fn partial_cmp(other: read Item): Ordering? { present(self.key.cmp(read other.key)) }
}
extend Item implements Ord {
    fn cmp(other: read Item): Ordering { self.key.cmp(read other.key) }
}

fn main(): i32 {
    var drops = 0
    {
        var items = vec.new<Item>()
        var i = 0
        while i < 33 {
            items.push(Item((32 - i) % 4, i + 0, core.ptr.from_mut(drops)))
            i += 1
        }
        items.sort()
        var at = 1usize
        while at < items.len() {
            if items[at - 1usize].key > items[at].key { return 1 }
            if items[at - 1usize].key == items[at].key &&
                items[at - 1usize].serial > items[at].serial { return 2 }
            at += 1usize
        }
        if drops != 0 { return 3 }
    }
    if drops != 33 { return 4 }
    var values = [Pair(2, 0), Pair(1, 1), Pair(2, 2), Pair(1, 3)]
    let slice = mut values[0usize..4usize]
    slice.sort_by_key(fn(value: read Pair): i32 { value.key })
    if values[0usize].serial != 1 || values[1usize].serial != 3 ||
        values[2usize].serial != 0 || values[3usize].serial != 2 { return 5 }
    let slice = mut values[0usize..4usize]
    slice.sort_by(fn(a: read Pair, b: read Pair): Ordering { b.key.cmp(read a.key) })
    if values[0usize].serial != 0 || values[1usize].serial != 2 ||
        values[2usize].serial != 1 || values[3usize].serial != 3 { return 6 }
    var calls = 0
    let call_count = core.ptr.from_mut(calls)
    let slice = mut values[0usize..4usize]
    slice.sort_by_cached_key(fn(value: read Pair): i32 {
        unsafe { *call_count += 1 }
        value.key
    })
    if calls != 4 || values[0usize].serial != 1 || values[1usize].serial != 3 ||
        values[2usize].serial != 0 || values[3usize].serial != 2 {
        return 9
    }
    var empty = vec.new<Pair>()
    empty.sort_by_key(fn(value: read Pair): i32 { value.key })
    empty.push(Pair(7, 9))
    empty.sort_by(fn(a: read Pair, b: read Pair): Ordering { a.key.cmp(read b.key) })
    if empty[0usize].serial != 9 { return 7 }
    empty.push(Pair(1, 10))
    empty.push(Pair(7, 11))
    empty.sort_by_key(fn(value: read Pair): i32 { value.key })
    if empty[0usize].serial != 10 || empty[1usize].serial != 9 ||
        empty[2usize].serial != 11 { return 8 }
    0
}
