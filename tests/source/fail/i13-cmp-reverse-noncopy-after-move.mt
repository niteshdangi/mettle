// expect-error: ownership 9:5 moved
import core.cmp.Reverse

type NotCopy { value: i32 }

fn main(): i32 {
    let first = Reverse(NotCopy(1))
    let second = first
    first.value.value
}
