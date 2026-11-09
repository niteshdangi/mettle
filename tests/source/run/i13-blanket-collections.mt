// expect-exit: 0
// profiles: debug release

import core.any.Any
import core.borrow.Borrow
import core.borrow.ToOwned
import core.convert.From
import core.convert.Into
import core.convert.{TryFrom, TryInto}

fn any_ok<T: Any>() {}
fn borrow_ok<T: unsized + Borrow<T>>() {}
fn owned_ok<T: ToOwned>() {}
fn from_ok<T: From<T>>() {}
fn into_ok<T: Into<T>>() {}
fn tryfrom_ok<T: TryFrom<T>>() {}
fn tryinto_ok<T: TryInto<T>>() {}
fn send_ok<T: Transferable>() {}
fn sync_ok<T: Shareable>() {}

fn main(): i32 {
    // alloc.binary_heap.BinaryHeap: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.binary_heap.BinaryHeap<i32>>()
    borrow_ok<alloc.binary_heap.BinaryHeap<i32>>()
    from_ok<alloc.binary_heap.BinaryHeap<i32>>()
    tryfrom_ok<alloc.binary_heap.BinaryHeap<i32>>()
    tryinto_ok<alloc.binary_heap.BinaryHeap<i32>>()
    into_ok<alloc.binary_heap.BinaryHeap<i32>>()
    send_ok<alloc.binary_heap.BinaryHeap<i32>>()
    sync_ok<alloc.binary_heap.BinaryHeap<i32>>()
    owned_ok<alloc.binary_heap.BinaryHeap<i32>>()

    // binary_heap::Drain = super.vec.Drain: Any Borrow From Into Send Sync
    borrow_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    from_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    into_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    send_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    sync_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()

    // binary_heap::IntoIter = vec.IntoIter: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.vec.IntoIter<i32>>()
    borrow_ok<alloc.vec.IntoIter<i32>>()
    from_ok<alloc.vec.IntoIter<i32>>()
    tryfrom_ok<alloc.vec.IntoIter<i32>>()
    tryinto_ok<alloc.vec.IntoIter<i32>>()
    into_ok<alloc.vec.IntoIter<i32>>()

    // binary_heap::Iter = SliceIter: Any Borrow From Into Send Sync ToOwned
    borrow_ok<core.slice.SliceIter<region static, i32>>()
    from_ok<core.slice.SliceIter<region static, i32>>()
    tryfrom_ok<core.slice.SliceIter<region static, i32>>()
    tryinto_ok<core.slice.SliceIter<region static, i32>>()
    into_ok<core.slice.SliceIter<region static, i32>>()
    send_ok<core.slice.SliceIter<region static, i32>>()
    sync_ok<core.slice.SliceIter<region static, i32>>()

    // alloc.btree.SortedMap (btree_map::BTreeMap): Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.btree.SortedMap<i32, i32>>()
    borrow_ok<alloc.btree.SortedMap<i32, i32>>()
    from_ok<alloc.btree.SortedMap<i32, i32>>()
    tryfrom_ok<alloc.btree.SortedMap<i32, i32>>()
    tryinto_ok<alloc.btree.SortedMap<i32, i32>>()
    into_ok<alloc.btree.SortedMap<i32, i32>>()
    send_ok<alloc.btree.SortedMap<i32, i32>>()
    sync_ok<alloc.btree.SortedMap<i32, i32>>()
    owned_ok<alloc.btree.SortedMap<i32, i32>>()

    // btree_map::Entry: Any Borrow From Into Send Sync
    borrow_ok<alloc.btree.Entry<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.btree.Entry<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.Entry<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.Entry<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.btree.Entry<region static, i32, i32, alloc.alloc.Global>>()

    // btree_map::IntoIter = MapIntoIter: Any Borrow From Into Send Sync
    any_ok<alloc.btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    borrow_ok<alloc.btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.btree.MapIntoIter<i32, i32, alloc.alloc.Global>>()

    // btree_map::Iter = EntryIter: Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.btree.EntryIter<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.btree.EntryIter<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.EntryIter<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.EntryIter<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.btree.EntryIter<region static, i32, i32, alloc.alloc.Global>>()

    // btree_map::IterMut: Any Borrow From Into Send Sync
    borrow_ok<alloc.btree.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.btree.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.btree.IterMut<region static, i32, i32, alloc.alloc.Global>>()

    // btree_map::Keys: Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.btree.Keys<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.btree.Keys<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.Keys<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.Keys<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.btree.Keys<region static, i32, i32, alloc.alloc.Global>>()

    // btree_map::Values: Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.btree.Values<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.btree.Values<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.Values<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.Values<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.btree.Values<region static, i32, i32, alloc.alloc.Global>>()

    // btree_set::BTreeSet = SortedSet: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.btree.SortedSet<i32>>()
    borrow_ok<alloc.btree.SortedSet<i32>>()
    from_ok<alloc.btree.SortedSet<i32>>()
    tryfrom_ok<alloc.btree.SortedSet<i32>>()
    tryinto_ok<alloc.btree.SortedSet<i32>>()
    into_ok<alloc.btree.SortedSet<i32>>()
    send_ok<alloc.btree.SortedSet<i32>>()
    sync_ok<alloc.btree.SortedSet<i32>>()
    owned_ok<alloc.btree.SortedSet<i32>>()

    // btree_set::IntoIter = SetIntoIter: Any Borrow From Into Send Sync
    any_ok<alloc.btree.SetIntoIter<i32, alloc.alloc.Global>>()
    borrow_ok<alloc.btree.SetIntoIter<i32, alloc.alloc.Global>>()
    from_ok<alloc.btree.SetIntoIter<i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.btree.SetIntoIter<i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.btree.SetIntoIter<i32, alloc.alloc.Global>>()
    into_ok<alloc.btree.SetIntoIter<i32, alloc.alloc.Global>>()

    // btree_set::Iter = Keys<K, Unit>: Any Borrow From Into Send Sync ToOwned

    // hash_map::Drain = MapDrain: Any Borrow From Into Send Sync
    borrow_ok<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>()
    send_ok<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>()
    sync_ok<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>()

    // hash_map::Entry: Any Borrow From Into Send Sync
    borrow_ok<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>()
    send_ok<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>()
    sync_ok<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>()

    // hash_map::HashMap = Map: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.hash_map.Map<i32, i32>>()
    borrow_ok<alloc.hash_map.Map<i32, i32>>()
    from_ok<alloc.hash_map.Map<i32, i32>>()
    tryfrom_ok<alloc.hash_map.Map<i32, i32>>()
    tryinto_ok<alloc.hash_map.Map<i32, i32>>()
    into_ok<alloc.hash_map.Map<i32, i32>>()
    send_ok<alloc.hash_map.Map<i32, i32>>()
    sync_ok<alloc.hash_map.Map<i32, i32>>()
    owned_ok<alloc.hash_map.Map<i32, i32>>()

    // hash_map::IntoIter = MapIntoIter: Any Borrow From Into Send Sync
    any_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    borrow_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    send_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()
    sync_ok<alloc.hash_map.MapIntoIter<i32, i32, alloc.alloc.Global>>()

    // hash_map::Iter: Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.hash_map.Iter<region static, i32, i32>>()
    from_ok<alloc.hash_map.Iter<region static, i32, i32>>()
    tryfrom_ok<alloc.hash_map.Iter<region static, i32, i32>>()
    tryinto_ok<alloc.hash_map.Iter<region static, i32, i32>>()
    into_ok<alloc.hash_map.Iter<region static, i32, i32>>()
    send_ok<alloc.hash_map.Iter<region static, i32, i32>>()
    sync_ok<alloc.hash_map.Iter<region static, i32, i32>>()

    // hash_map::IterMut: Any Borrow From Into Send Sync
    borrow_ok<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    from_ok<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    into_ok<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    send_ok<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>()
    sync_ok<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>()

    // hash_map::Keys: Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.hash_map.Keys<region static, i32, i32>>()
    from_ok<alloc.hash_map.Keys<region static, i32, i32>>()
    tryfrom_ok<alloc.hash_map.Keys<region static, i32, i32>>()
    tryinto_ok<alloc.hash_map.Keys<region static, i32, i32>>()
    into_ok<alloc.hash_map.Keys<region static, i32, i32>>()
    send_ok<alloc.hash_map.Keys<region static, i32, i32>>()
    sync_ok<alloc.hash_map.Keys<region static, i32, i32>>()

    // hash_map::Values: Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.hash_map.Values<region static, i32, i32>>()
    from_ok<alloc.hash_map.Values<region static, i32, i32>>()
    tryfrom_ok<alloc.hash_map.Values<region static, i32, i32>>()
    tryinto_ok<alloc.hash_map.Values<region static, i32, i32>>()
    into_ok<alloc.hash_map.Values<region static, i32, i32>>()
    send_ok<alloc.hash_map.Values<region static, i32, i32>>()
    sync_ok<alloc.hash_map.Values<region static, i32, i32>>()

    // hash_set::Drain = SetDrain: Any Borrow From Into Send Sync
    borrow_ok<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>()
    from_ok<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>()
    into_ok<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>()
    send_ok<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>()
    sync_ok<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>()

    // hash_set::HashSet = Set: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.hash_map.Set<i32>>()
    borrow_ok<alloc.hash_map.Set<i32>>()
    from_ok<alloc.hash_map.Set<i32>>()
    tryfrom_ok<alloc.hash_map.Set<i32>>()
    tryinto_ok<alloc.hash_map.Set<i32>>()
    into_ok<alloc.hash_map.Set<i32>>()
    send_ok<alloc.hash_map.Set<i32>>()
    sync_ok<alloc.hash_map.Set<i32>>()
    owned_ok<alloc.hash_map.Set<i32>>()

    // hash_set::IntoIter = SetIntoIter: Any Borrow From Into Send Sync
    any_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    borrow_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    from_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    into_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    send_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()
    sync_ok<alloc.hash_map.SetIntoIter<i32, alloc.alloc.Global>>()

    // hash_set::Iter = Keys<K, Unit>: Any Borrow From Into Send Sync ToOwned

    // vec_deque::Drain = DequeDrain: Any Borrow From Into Send Sync
    borrow_ok<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>()
    from_ok<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>()
    into_ok<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>()
    send_ok<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>()
    sync_ok<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>()

    // vec_deque::IntoIter = DequeIntoIter: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.vec_deque.DequeIntoIter<i32>>()
    borrow_ok<alloc.vec_deque.DequeIntoIter<i32>>()
    from_ok<alloc.vec_deque.DequeIntoIter<i32>>()
    tryfrom_ok<alloc.vec_deque.DequeIntoIter<i32>>()
    tryinto_ok<alloc.vec_deque.DequeIntoIter<i32>>()
    into_ok<alloc.vec_deque.DequeIntoIter<i32>>()
    send_ok<alloc.vec_deque.DequeIntoIter<i32>>()
    sync_ok<alloc.vec_deque.DequeIntoIter<i32>>()

    // vec_deque::Iter = DequeIter: Any Borrow From Into Send Sync ToOwned
    borrow_ok<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>()
    from_ok<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>()
    into_ok<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>()
    send_ok<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>()
    sync_ok<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>()

    // vec_deque::IterMut: Any Borrow From Into Send Sync
    borrow_ok<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>()
    from_ok<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>()
    into_ok<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>()
    send_ok<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>()
    sync_ok<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>()

    // vec_deque::VecDeque = Deque: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.vec_deque.Deque<i32>>()
    borrow_ok<alloc.vec_deque.Deque<i32>>()
    from_ok<alloc.vec_deque.Deque<i32>>()
    tryfrom_ok<alloc.vec_deque.Deque<i32>>()
    tryinto_ok<alloc.vec_deque.Deque<i32>>()
    into_ok<alloc.vec_deque.Deque<i32>>()
    send_ok<alloc.vec_deque.Deque<i32>>()
    sync_ok<alloc.vec_deque.Deque<i32>>()
    owned_ok<alloc.vec_deque.Deque<i32>>()

    // vec::Drain: Any Borrow From Into Send Sync
    borrow_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    from_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    tryfrom_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    tryinto_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    into_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    send_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()
    sync_ok<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>()

    // vec::IntoIter: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.vec.IntoIter<i32>>()
    borrow_ok<alloc.vec.IntoIter<i32>>()
    from_ok<alloc.vec.IntoIter<i32>>()
    tryfrom_ok<alloc.vec.IntoIter<i32>>()
    tryinto_ok<alloc.vec.IntoIter<i32>>()
    into_ok<alloc.vec.IntoIter<i32>>()

    // vec::Vec = List: Any Borrow From Into Send Sync ToOwned
    any_ok<alloc.vec.List<i32>>()
    borrow_ok<alloc.vec.List<i32>>()
    from_ok<alloc.vec.List<i32>>()
    tryfrom_ok<alloc.vec.List<i32>>()
    tryinto_ok<alloc.vec.List<i32>>()
    into_ok<alloc.vec.List<i32>>()
    send_ok<alloc.vec.List<i32>>()
    sync_ok<alloc.vec.List<i32>>()
    owned_ok<alloc.vec.List<i32>>()

    // string::Drain = StringDrain: Any Borrow From Into Send Sync
    borrow_ok<alloc.string.StringDrain<region static, alloc.alloc.Global>>()
    from_ok<alloc.string.StringDrain<region static, alloc.alloc.Global>>()
    tryfrom_ok<alloc.string.StringDrain<region static, alloc.alloc.Global>>()
    tryinto_ok<alloc.string.StringDrain<region static, alloc.alloc.Global>>()
    into_ok<alloc.string.StringDrain<region static, alloc.alloc.Global>>()
    send_ok<alloc.string.StringDrain<region static, alloc.alloc.Global>>()
    sync_ok<alloc.string.StringDrain<region static, alloc.alloc.Global>>()
    0
}
