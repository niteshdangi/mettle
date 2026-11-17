// profiles: debug release
import std.panic.CatchResult

copy type Pair { value: i32; flag: bool }
type ViewGuard<region r> {
    value: read i32 from r
    result: ptr<mut i32>
    drop { unsafe { *self.result += *self.value } }
}
type PointerGuard {
    value: ptr<read i32>
    result: ptr<mut i32>
    drop { unsafe { *self.result += *self.value } }
}

fn fail(result: ptr<mut i32>): Unit {
    let pair = Pair(40, true)
    let stored = 11
    let first = ViewGuard(read pair.value, result)
    let second = PointerGuard(core.ptr.from_ref(stored), result)
    if pair.flag { panic("cleanup local") }
}

fn ordinary(): i32 {
    var pair = Pair(1, false)
    var i = 0
    while i < 10 {
        pair.value += i
        pair.flag = !pair.flag
        i += 1
    }
    if pair.flag { 0 } else { pair.value }
}

fn main(): i32 {
    var result = 0
    let pointer = core.ptr.from_mut(result)
    let caught = std.panic.catch_panic(fn(): Unit { fail(pointer) })
    match take caught {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if result != 51 { return 2 }
    if ordinary() != 46 { return 3 }
    0
}
