// expect-error: ownership 15:14 moved
import alloc.alloc.{Allocator, Layout, AllocError}
import alloc.vec.List
type Arena {}
extend Arena implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError { throw AllocError(0usize, 1usize) }
    mut fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {}
    mut fn grow(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError { throw AllocError(0usize, 1usize) }
    mut fn shrink(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError { throw AllocError(0usize, 1usize) }
}
fn main(): i32 {
    let arena = Arena()
    let _first = List<i32, Arena>(allocator: take arena)
    let _second = List<i32, Arena>(
        take arena
    )
    0
}
