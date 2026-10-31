import std.sync.{once, once_lock}
import alloc.boxed

type Payload { count: ptr<mut i32>; value: i32 }
extend Payload {
    pub take fn consume(): i32 {
        unsafe { *self.count += 1 }
        self.value
    }
}

fn main(): i32 {
    var called = 0
    let initialized = once.new()
    let first = Payload(core.ptr.from_mut(called), 7)
    initialized.call_once(take fn(): Unit { let _ = first.consume() })
    if called != 1 || !initialized.is_completed() { return 1 }
    let skipped = Payload(core.ptr.from_mut(called), 8)
    initialized.call_once(take fn(): Unit { let _ = skipped.consume() })
    if called != 1 { return 2 }

    let forced = once.new()
    let owned = boxed.new(9)
    forced.call_once_force(take fn(state: once.OnceState): Unit {
        if state.is_poisoned() { panic("fresh once was poisoned") }
        let _ = owned.into_inner()
    })
    if !forced.is_completed() { return 3 }

    let cell = once_lock.new<i32>()
    let owned = boxed.new(42)
    if *cell.get_or_init(take fn(): i32 { owned.into_inner() }) != 42 { return 4 }
    let ignored = Payload(core.ptr.from_mut(called), 99)
    if *cell.get_or_init(take fn(): i32 { ignored.consume() }) != 42 || called != 1 {
        return 5
    }
    0
}
