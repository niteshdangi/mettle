// expect-exit: 101
import core.num

fn main(): i32 {
    let _ = num.Wrapping(1i32) % num.Wrapping(0i32)
    0
}
