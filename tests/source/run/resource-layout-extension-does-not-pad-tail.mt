import alloc.alloc.{Layout, extend_layout, layout_from_size_align}

fn layout(size: usize, align: usize): Layout {
    match capture layout_from_size_align(size, align) {
        success(value) => value,
        failure(_) => core.panic.panic("invalid fixture layout")
    }
}

fn main(): i32 {
    let (combined, offset) = match capture extend_layout(layout(8usize, 8usize), layout(1usize, 1usize)) {
        success(value) => value,
        failure(_) => { return 1 }
    }
    if offset != 8usize || combined.size() != 9usize || combined.align() != 8usize {
        return 2
    }
    let (continued, next) = match capture extend_layout(combined, layout(1usize, 1usize)) {
        success(value) => value,
        failure(_) => { return 3 }
    }
    if next != 9usize || continued.size() != 10usize { return 4 }
    let padded = combined.pad_to_align()
    if padded.size() != 16usize || padded.align() != 8usize { return 5 }
    0
}
