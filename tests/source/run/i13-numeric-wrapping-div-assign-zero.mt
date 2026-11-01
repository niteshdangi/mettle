// profiles: debug release
// expect-exit: trap
import core.num.Wrapping
import core.ops.DivAssign

fn main(): i32 {
    var result = Wrapping(1i128)
    result /= Wrapping(0i128)
    result.value as i32
}
