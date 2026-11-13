// expect-error: ownership 9:5 moved
import core.future.Poll

type Owned { value: i32 }

fn main(): i32 {
    let first = Poll.Ready(Owned(1))
    let second = first
    first.is_ready() as i32
}
