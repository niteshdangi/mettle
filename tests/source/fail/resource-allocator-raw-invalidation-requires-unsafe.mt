// expect-error: unsafe 7:5 requires an unsafe block
// expect-error: unsafe 11:9 requires an unsafe block
// expect-error: unsafe 15:9 requires an unsafe block
import alloc.alloc.{Allocator, Global, Layout, AllocError}

fn reject_deallocate(mut allocator: Global, pointer: ptr<mut u8>, layout: Layout): Unit {
    allocator.deallocate(pointer, layout)
}

fn reject_grow(mut allocator: Global, pointer: ptr<mut u8>, layout: Layout): ptr<mut u8> throws AllocError {
    try allocator.grow(pointer, layout, layout.size())
}

fn reject_shrink(mut allocator: Global, pointer: ptr<mut u8>, layout: Layout): ptr<mut u8> throws AllocError {
    try allocator.shrink(pointer, layout, layout.size())
}

fn main(): i32 { 0 }
