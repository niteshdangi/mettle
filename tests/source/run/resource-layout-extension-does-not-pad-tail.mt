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

    let unpadded = layout(3usize, 2usize)
    let (repeated, stride) = match capture unpadded.repeat(3usize) {
        success(value) => value,
        failure(_) => { return 6 }
    }
    if stride != 4usize || repeated.size() != 11usize || repeated.align() != 2usize {
        return 7
    }
    let empty = match capture unpadded.repeat(0usize) {
        success(value) => value,
        failure(_) => { return 8 }
    }
    if empty.0.size() != 0usize || empty.1 != 4usize { return 9 }

    let packed = match capture unpadded.repeat_packed(3usize) {
        success(value) => value,
        failure(_) => { return 10 }
    }
    if packed.size() != 9usize || packed.align() != 2usize { return 11 }

    let packed_extension = match capture unpadded.extend_packed(layout(1usize, 8usize)) {
        success(value) => value,
        failure(_) => { return 12 }
    }
    if packed_extension.size() != 4usize || packed_extension.align() != 2usize {
        return 13
    }

    let aligned = match capture unpadded.align_to(8usize) {
        success(value) => value,
        failure(_) => { return 14 }
    }
    if aligned.size() != 3usize || aligned.align() != 8usize { return 15 }
    match capture unpadded.align_to(3usize) {
        success(_) => { return 16 },
        failure(_) => {}
    }
    0
}
