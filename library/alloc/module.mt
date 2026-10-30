// Root of the native `alloc` library: depends on `core` and an explicit
// allocator hook (see `alloc::alloc`), never on an operating system.
pub module alloc;
pub module boxed;
pub module rc;
pub module arc;
pub module binary_heap;
pub module btree;
pub module hash_map;
pub module string;
pub module linked_list;
pub module vec;
pub module vec_deque;
