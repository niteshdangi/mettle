// expect-exit: trap
import core.cmp

fn main(): i32 {
    let _ = cmp.clamp(0i32, 3i32, 2i32)
    0
}
