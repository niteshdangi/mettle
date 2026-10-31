// expect-exit: trap
import core.cmp.Ord

fn main(): i32 {
    let _ = 0i32.(Ord).clamp(3i32, 2i32)
    0
}
