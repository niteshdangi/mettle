type Slot<region r> { value: read i32 from r }
fn exchange<region r>(mut slot: Slot<region r>, take next: Slot<region r>): Slot<region r> {
    core.mem.replace(mut slot, take next)
}
fn swap<region r>(mut first: Slot<region r>, mut second: Slot<region r>) {
    core.mem.swap(mut first, mut second)
}
fn main(): i32 {
    let first = 41
    let second = 42
    var slot = Slot(read first)
    let previous = exchange(mut slot, Slot(read second))
    var other = Slot(read first)
    swap(mut slot, mut other)
    if *previous.value == 41 && *slot.value == 41 && *other.value == 42 { 0 } else { 1 }
}
