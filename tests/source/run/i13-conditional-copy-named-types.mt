// profiles: debug release
import core.cmp.Reverse
import core.future.Poll

type Owned { value: i32 }

fn main(): i32 {
    let low = Reverse(1)
    let low_twin = low
    if low.value != low_twin.value { return 1 }
    let ready = Poll.Ready(2)
    let ready_twin = ready
    if ready != ready_twin { return 2 }
    let pending: Poll<i32> = Poll.Pending
    let pending_twin = pending
    if pending != pending_twin { return 3 }
    let held = Reverse(Owned(3))
    let moved = held
    if moved.value.value != 3 { return 4 }
    0
}
