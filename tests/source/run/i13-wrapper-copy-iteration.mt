// profiles: debug release

import core.ops.Deref

fn main(): i32 {
    let some: i32? = present(4)
    let outcome: (Outcome<i32, i32>) = success(5)
    let five: (Outcome<i32, i32>) = success(5)
    let twenty_two: (Outcome<i32, i32>) = success(22)
    let held = core.mem.ManuallyDrop.new(6)
    let (some_twin, outcome_twin, held_twin) = (some, outcome, held)
    if some_twin != some || outcome_twin != outcome || *held_twin.deref() != *held.deref() { return 1 }
    if some != present(4) || outcome != five || *held.deref() != 6 { return 2 }

    var slot: i32? = present(1)
    for value in mut slot { *value += 10 }
    if slot != present(11) { return 3 }
    var result: (Outcome<i32, i32>) = success(2)
    for value in mut result { *value += 20 }
    if result != twenty_two { return 4 }
    0
}
