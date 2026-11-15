import alloc.btree
import core.clone.Clone
import core.iter.Iterator

fn main(): i32 {
    var map = btree.new<i32, i32>()
    map.insert(1, 10)
    map.insert(2, 20)
    map.insert(3, 30)
    var map_range = map.range(core.iter.range(1, 4))
    if map_range.next().or_panic().key != 1 { return 1 }
    var map_clone = map_range.clone()
    if map_range.next().or_panic().key != 2 ||
        map_clone.next().or_panic().key != 2 ||
        map_range.next().or_panic().key != 3 ||
        map_clone.next().or_panic().key != 3 ||
        map_range.next().is_present() || map_clone.next().is_present() {
        return 2
    }

    var set = btree.set_new<i32>()
    set.insert(1)
    set.insert(2)
    set.insert(3)
    var set_range = set.range(core.iter.range(1, 4))
    if set_range.next().or_panic().key != 1 { return 3 }
    var set_clone = set_range.clone()
    if set_range.next().or_panic().key != 2 ||
        set_clone.next().or_panic().key != 2 ||
        set_range.next().or_panic().key != 3 ||
        set_clone.next().or_panic().key != 3 ||
        set_range.next().is_present() || set_clone.next().is_present() {
        return 4
    }
    0
}
