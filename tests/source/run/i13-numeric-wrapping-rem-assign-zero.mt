// profiles: debug release
// expect-exit: trap
import core.num.Wrapping
import core.ops.RemAssign

fn main(): i32 {
    var result = Wrapping(1u16)
    result %= 0u16
    result.value as i32
}
