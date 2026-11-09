// profiles: debug release
import alloc.btree
import alloc.hash_map
import alloc.vec_deque
import core.clone.Clone
import core.convert.From
import core.default.Default
import core.fmt.Debug
import core.iter.{ExactSizeIterator, Iterator, Iterable}

fn default_value<T: Default>(): T { T.(Default).default() }
fn require_debug<T: Debug>(read value: T): bool { true }
fn exact_len<I: ExactSizeIterator>(read items: I): usize {
    I.(ExactSizeIterator).len(items)
}

fn check_btree_defaults<region r>(
    read map: btree.SortedMap<i32, i32> from r
): bool {
    var entries: btree.EntryIter<region r, i32, i32, alloc.alloc.Global> =
        default_value<btree.EntryIter<region r, i32, i32, alloc.alloc.Global>>()
    var keys: btree.Keys<region r, i32, i32, alloc.alloc.Global> =
        default_value<btree.Keys<region r, i32, i32, alloc.alloc.Global>>()
    var values: btree.Values<region r, i32, i32, alloc.alloc.Global> =
        default_value<btree.Values<region r, i32, i32, alloc.alloc.Global>>()
    var entries_mut: btree.IterMut<region r, i32, i32, alloc.alloc.Global> =
        default_value<btree.IterMut<region r, i32, i32, alloc.alloc.Global>>()
    var values_mut: btree.ValuesMut<region r, i32, i32, alloc.alloc.Global> =
        default_value<btree.ValuesMut<region r, i32, i32, alloc.alloc.Global>>()
    var entries_copy = entries.clone()
    var keys_copy = keys.clone()
    var values_copy = values.clone()
    require_debug(read entries)
    require_debug(read keys)
    require_debug(read values)
    require_debug(read entries_mut)
    require_debug(read values_mut)
    entries.size_hint() == (0usize, present(0usize)) &&
        exact_len(read entries) == 0usize &&
        exact_len(read keys) == 0usize &&
        exact_len(read values) == 0usize &&
        exact_len(read entries_mut) == 0usize &&
        exact_len(read values_mut) == 0usize &&
        keys.size_hint() == (0usize, present(0usize)) &&
        values.size_hint() == (0usize, present(0usize)) &&
        entries_mut.size_hint() == (0usize, present(0usize)) &&
        values_mut.size_hint() == (0usize, present(0usize)) &&
        !entries_copy.next().is_present() &&
        !keys_copy.next().is_present() &&
        !values_copy.next().is_present() &&
        !entries_mut.next().is_present() &&
        !values_mut.next().is_present()
}

fn check_btree_set_defaults<region r>(
    read set: btree.SortedSet<i32> from r
): bool {
    var items: btree.Keys<region r, i32, Unit, alloc.alloc.Global> =
        default_value<btree.Keys<region r, i32, Unit, alloc.alloc.Global>>()
    var items_copy = items.clone()
    require_debug(read items) &&
        items.size_hint() == (0usize, present(0usize)) &&
        exact_len(read items) == 0usize &&
        !items.next().is_present() &&
        !items_copy.next_back().is_present() &&
        set.iter().size_hint() == (set.len(), present(set.len()))
}

fn check_hash_set_defaults<region r>(
    read set: hash_map.Set<i32> from r
): bool {
    var items: hash_map.Keys<region r, i32, Unit> =
        default_value<hash_map.Keys<region r, i32, Unit>>()
    var items_copy = items.clone()
    require_debug(read items) &&
        items.size_hint() == (0usize, present(0usize)) &&
        exact_len(read items) == 0usize &&
        !items.next().is_present() &&
        !items_copy.next().is_present() &&
        set.iter().size_hint() == (set.len(), present(set.len()))
}

fn check_deque_defaults<region r>(
    read deque: vec_deque.Deque<i32> from r
): bool {
    var items: vec_deque.DequeIter<region r, i32, alloc.alloc.Global> =
        default_value<vec_deque.DequeIter<region r, i32, alloc.alloc.Global>>()
    var items_mut: vec_deque.DequeIterMut<region r, i32, alloc.alloc.Global> =
        default_value<vec_deque.DequeIterMut<region r, i32, alloc.alloc.Global>>()
    var items_copy = items.clone()
    require_debug(read items)
    require_debug(read items_mut)
    items.size_hint() == (0usize, present(0usize)) &&
        items_mut.size_hint() == (0usize, present(0usize)) &&
        exact_len(read items) == 0usize &&
        exact_len(read items_mut) == 0usize &&
        !items_copy.next().is_present() &&
        !items_mut.next().is_present()
}

fn main(): i32 {
    let map = btree.new<i32, i32>()
    if !check_btree_defaults(map) { return 1 }
    let tree_set = btree.set_new<i32>()
    if !check_btree_set_defaults(tree_set) { return 13 }
    var tree_into: btree.MapIntoIter<i32, i32, alloc.alloc.Global> =
        default_value<btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    var tree_keys: btree.IntoKeys<i32, i32, alloc.alloc.Global> =
        default_value<btree.IntoKeys<i32, i32, alloc.alloc.Global>>()
    var tree_values: btree.IntoValues<i32, i32, alloc.alloc.Global> =
        default_value<btree.IntoValues<i32, i32, alloc.alloc.Global>>()
    var tree_set: btree.SetIntoIter<i32, alloc.alloc.Global> =
        default_value<btree.SetIntoIter<i32, alloc.alloc.Global>>()
    if !require_debug(read tree_into) ||
        !require_debug(read tree_set) ||
        exact_len(read tree_into) != 0usize ||
        exact_len(read tree_keys) != 0usize ||
        exact_len(read tree_values) != 0usize ||
        exact_len(read tree_set) != 0usize ||
        tree_into.next().is_present() ||
        tree_keys.next().is_present() ||
        tree_values.next().is_present() ||
        tree_set.next().is_present() {
        return 11
    }
    let hash_set = hash_map.set_new<i32>()
    if !check_hash_set_defaults(hash_set) { return 14 }
    var hash_into: hash_map.MapIntoIter<i32, i32, alloc.alloc.Global> =
        default_value<hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    var hash_keys: hash_map.IntoKeys<i32, i32, alloc.alloc.Global> =
        default_value<hash_map.IntoKeys<i32, i32, alloc.alloc.Global>>()
    var hash_values: hash_map.IntoValues<i32, i32, alloc.alloc.Global> =
        default_value<hash_map.IntoValues<i32, i32, alloc.alloc.Global>>()
    var hash_set: hash_map.SetIntoIter<i32, alloc.alloc.Global> =
        default_value<hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    if !require_debug(read hash_into) ||
        !require_debug(read hash_keys) ||
        !require_debug(read hash_values) ||
        !require_debug(read hash_set) ||
        exact_len(read hash_into) != 0usize ||
        exact_len(read hash_keys) != 0usize ||
        exact_len(read hash_values) != 0usize ||
        exact_len(read hash_set) != 0usize ||
        hash_into.next().is_present() ||
        hash_keys.next().is_present() ||
        hash_values.next().is_present() ||
        hash_set.next().is_present() {
        return 12
    }
    let deque = vec_deque.new<i32>()
    if !check_deque_defaults(deque) { return 2 }
    let array_deque = vec_deque.Deque<i32>.(From<[i32; 3]>).from([3, 1, 2])
    if array_deque.len() != 3usize ||
        array_deque[0usize] != 3 ||
        array_deque[1usize] != 1 ||
        array_deque[2usize] != 2 {
        return 3
    }
    var empty_owned: vec_deque.DequeIntoIter<i32, alloc.alloc.Global> =
        default_value<vec_deque.DequeIntoIter<i32, alloc.alloc.Global>>()
    if !require_debug(read empty_owned) ||
        empty_owned.size_hint() != (0usize, present(0usize)) ||
        exact_len(read empty_owned) != 0usize ||
        empty_owned.next().is_present() {
        return 4
    }
    var owned = array_deque.into_iter()
    var copied = owned.clone()
    if !require_debug(read owned) ||
        owned.size_hint() != (3usize, present(3usize)) ||
        exact_len(read owned) != 3usize {
        return 5
    }
    match owned.next() {
        present(value) => { if value != 3 { return 6 } },
        none => { return 7 }
    }
    match copied.next_back() {
        present(value) => { if value != 2 { return 8 } },
        none => { return 9 }
    }
    if owned.size_hint() != (2usize, present(2usize)) ||
        copied.size_hint() != (2usize, present(2usize)) {
        return 10
    }
    0
}
