// The collection vocabulary: one implementation each, reexported from its
// owning module. `List`, `Map` and `Set` are also in the prelude.
pub import super.vec.List
pub import super.hash_map.{Map, Set}
pub import super.btree.{SortedMap, SortedSet}
pub import super.vec_deque.Deque
pub import super.linked_list.LinkedList
pub import super.binary_heap.BinaryHeap
