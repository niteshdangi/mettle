import core.clone.Clone

fn main(): i32 {
    let first: local shared i32 = local shared 23
    let second = first.clone()
    if first.strong_count() == 2usize && second.strong_count() == 2usize {
        0
    } else {
        1
    }
}
