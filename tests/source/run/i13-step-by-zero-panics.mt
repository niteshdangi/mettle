// expect-exit: 101
import core.iter

fn main(): i32 {
    let _ = iter.range(0, 3).step_by(0usize)
    0
}
