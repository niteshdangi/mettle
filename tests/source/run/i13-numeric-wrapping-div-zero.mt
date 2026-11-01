// profiles: debug release
// expect-exit: trap
import core.num.Wrapping
import core.ops.Div

fn main(): i32 {
    let result = Wrapping(1i8) / Wrapping(0i8)
    result.value as i32
}
