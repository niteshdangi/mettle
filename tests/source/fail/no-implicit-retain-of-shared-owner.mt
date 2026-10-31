// expect-error: ownership 6:8 moved

fn main(): i32 {
    let first = alloc.rc.new(42)
    let second = first
    if first.strong_count() == 1usize && second.strong_count() == 1usize {
        0
    } else { 1 }
}
