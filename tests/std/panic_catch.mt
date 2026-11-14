// expect-stdout: hook: main caught\nhook: replacement cleanup\nhook: nested inner\nhook: nested outer\ncontinued\n
import alloc.arc
import alloc.arc.Shared
import std.panic.CatchResult

type Counted {
    drops: Shared<core.sync.atomic.AtomicUsize>
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

type Replacement {
    drops: Shared<core.sync.atomic.AtomicUsize>
    value: i32
    panic_on_drop: bool
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
        if self.panic_on_drop { panic("replacement cleanup") }
    }
}

fn overwrite(mut value: Replacement): Unit {
    let drops = value.drops.retain()
    value = Replacement(drops, 42, false)
}

unsafe extern "C" fn hook(message: ptr<read u8>, length: u64): Unit {
    std.io.print("hook: ")
    let _written = unsafe { std.sys.write(1, message, length as usize) }
    std.io.print("\n")
}

fn main(): i32 {
    let previous = std.panic.take_hook()
    match previous {
        none => {},
        present(_) => { return 1 }
    }
    std.panic.set_hook(hook)
    let previous = match std.panic.take_hook() {
        present(old) => old,
        none => { return 2 }
    }
    std.panic.set_hook(previous)

    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let caught = std.panic.catch_panic(fn(): i32 {
        let _local = Counted(drops.retain())
        panic("main caught")
        7
    })
    match take caught {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 3 }
            let message = info.message()
            if message.len() != 11usize || !message.starts_with("main caught") {
                return 4
            }
        },
        CatchResult.Returned(_) => { return 5 }
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 6 }

    var value = Replacement(drops.retain(), 1, true)
    let restored = std.panic.catch_panic(fn(): i32 {
        overwrite(mut value)
        0
    })
    match take restored {
        CatchResult.Panicked(info) => {
            if !info.message().starts_with("replacement cleanup") {
                return 11
            }
        },
        CatchResult.Returned(_) => { return 12 }
    }
    if value.value != 42 || value.panic_on_drop { return 13 }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize { return 14 }

    let outer = std.panic.catch_panic(take fn(): i32 {
        let inner = std.panic.catch_panic(take fn(): i32 {
            panic("nested inner")
            0
        })
        match take inner {
            CatchResult.Panicked(info) => {
                if info.code() != 101 || info.message().len() != 12usize {
                    panic("incorrect nested payload")
                }
            },
            CatchResult.Returned(_) => { panic("inner panic was not caught") }
        }
        panic("nested outer")
        42
    })
    match take outer {
        CatchResult.Panicked(info) => {
            if info.code() != 101 || info.message().len() != 12usize {
                return 7
            }
        },
        CatchResult.Returned(_) => { return 8 }
    }

    match std.panic.catch_panic(take fn(): i32 { 42 }) {
        CatchResult.Returned(value) => { if value != 42 { return 9 } },
        CatchResult.Panicked(_) => { return 10 }
    }
    std.panic.reset_hook()
    std.io.print("continued\n")
    0
}
