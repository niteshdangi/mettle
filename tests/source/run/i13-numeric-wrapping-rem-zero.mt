// profiles: debug release
// expect-exit: trap
import core.num.Wrapping
import core.ops.Rem

fn main(): i32 {
    let result = Wrapping(1u128) % Wrapping(0u128)
    result.value as i32
}
