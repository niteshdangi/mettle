// expect-error: type 11:13 no constructor of 'List' accepts this argument shape
import alloc.alloc.{Allocator, Layout, AllocError}
import alloc.vec.List
type Arena {}
unsafe extend Arena implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError { throw AllocError(0usize, 1usize) }
    mut unsafe fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {}
    mut unsafe fn grow(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError { throw AllocError(0usize, 1usize) }
    mut unsafe fn shrink(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError { throw AllocError(0usize, 1usize) }
}
fn main() { List<i32, Arena>() }
