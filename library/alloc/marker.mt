import core.marker.{RefUnwindSafe, UnwindSafe}
import super.alloc.Allocator
import super.boxed.{Box, Pinned}

unsafe extend<T: UnwindSafe + unsized, A: Allocator + UnwindSafe>
    Box<T, A> implements UnwindSafe {}
unsafe extend<T: RefUnwindSafe + unsized, A: Allocator + RefUnwindSafe>
    Box<T, A> implements RefUnwindSafe {}

unsafe extend<region r, T: core.cmp.Ord + RefUnwindSafe, A: Allocator + RefUnwindSafe> super.binary_heap.PeekMut<region r, T, A> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator, F: RefUnwindSafe> super.btree.MapExtractIf<region r, K, V, A, F> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator> super.btree.RangeMut<region r, K, V, A> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator> super.btree.IterMut<region r, K, V, A> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator> super.btree.ValuesMut<region r, K, V, A> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, A: Allocator, F: RefUnwindSafe> super.btree.SetExtractIf<region r, K, A, F> implements RefUnwindSafe {}

unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator + RefUnwindSafe, S: core.hash.BuildHasher, F: RefUnwindSafe> super.hash_map.ExtractIf<region r, K, V, A, S, F> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, A: Allocator + RefUnwindSafe, S: core.hash.BuildHasher, F: RefUnwindSafe> super.hash_map.SetExtractIf<region r, K, A, S, F> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator, S: core.hash.BuildHasher> super.hash_map.IterMut<region r, K, V, A, S> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator, S: core.hash.BuildHasher> super.hash_map.ValuesMut<region r, K, V, A, S> implements RefUnwindSafe {}

unsafe extend<region r, T: RefUnwindSafe, A: Allocator + RefUnwindSafe, F: RefUnwindSafe> super.linked_list.LinkedListExtractIf<region r, T, A, F> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, A: Allocator> super.linked_list.ListIterMut<region r, T, A> implements RefUnwindSafe {}

unsafe extend<region r, T: RefUnwindSafe, A: Allocator + RefUnwindSafe> super.vec.Drain<region r, T, A> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, A: Allocator + RefUnwindSafe> super.vec.Drain<region r, T, A> implements UnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, A: Allocator + RefUnwindSafe, F: RefUnwindSafe> super.vec.ExtractIf<region r, T, A, F> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, A: Allocator + RefUnwindSafe> super.vec_deque.DequeDrain<region r, T, A> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, A: Allocator + RefUnwindSafe> super.vec_deque.DequeDrain<region r, T, A> implements UnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, A: Allocator> super.vec_deque.DequeIterMut<region r, T, A> implements RefUnwindSafe {}

unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator> super.btree.KeyRange<region r, K, V, A> implements UnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator> super.btree.KeyRange<region r, K, V, A> implements RefUnwindSafe {}
unsafe extend<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: Allocator> super.btree.RangeMut<region r, K, V, A> implements UnwindSafe {}

unsafe extend<T: UnwindSafe + unsized, A: Allocator + UnwindSafe>
    Pinned<T, A> implements UnwindSafe {}
unsafe extend<T: RefUnwindSafe + unsized, A: Allocator + RefUnwindSafe>
    Pinned<T, A> implements RefUnwindSafe {}
