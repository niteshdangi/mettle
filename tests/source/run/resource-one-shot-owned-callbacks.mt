import core.{cell, option, outcome, pin}
import core.future.Poll

type Guard {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}
fn consume(take guard: Guard): Unit {}
type Pair { value: i32 }

fn main(): i32 {
    var drops = 0
    var optional: i32? = none
    {
        let guard = Guard(core.ptr.from_mut(drops))
        let value = optional.get_or_insert_with(take fn(): i32 {
            consume(guard)
            7
        })
        if *value != 7 { return 1 }
    }
    {
        let guard = Guard(core.ptr.from_mut(drops))
        let value = optional.get_or_insert_with(take fn(): i32 {
            consume(guard)
            core.panic.panic("unselected initializer")
        })
        if *value != 7 || drops != 2 { return 2 }
    }
    let mapped_guard = Guard(core.ptr.from_mut(drops))
    let mapped = optional.map(take fn(take value: i32): i32 {
        consume(mapped_guard)
        value + 1
    })
    if mapped.or_panic() != 8 { return 3 }

    let outcome_guard = Guard(core.ptr.from_mut(drops))
    let result: Outcome<i32, i32> = success(11)
    let converted = result.map(take fn(take value: i32): i32 {
        consume(outcome_guard)
        value + 2
    })
    if converted.or_panic() != 13 { return 4 }

    let poll_guard = Guard(core.ptr.from_mut(drops))
    match take Poll.Ready(17).map(take fn(take value: i32): i32 {
        consume(poll_guard)
        value + 2
    }) {
        Poll.Ready(value) => { if value != 19 { return 5 } },
        Poll.Pending => { return 6 }
    }

    let replacement_guard = Guard(core.ptr.from_mut(drops))
    let value = core.cell.RefCell.new(23)
    let old = value.replace_with(take fn(mut previous: i32): i32 {
        consume(replacement_guard)
        previous += 1
        previous + 5
    })
    if old != 24 || *value.borrow().get_ref() != 29 { return 7 }

    var pair = Pair(31)
    let source = core.pin.Pin.new(mut pair)
    let projection_guard = Guard(core.ptr.from_mut(drops))
    let projected = unsafe {
        source.map_unchecked(take fn(read item: Pair): read i32 from item {
            consume(projection_guard)
            read item.value
        })
    }
    if *projected.get_ref() != 31 || drops != 7 { return 8 }
    0
}
