// profiles: debug release
import core.clone.Clone
import core.default.Default
import std.panic.{catch_panic, CatchResult}

static mut DROPS: usize = 0usize
static mut DEFAULT_CALLS: usize = 0usize

type Guard {
    fail_clone: bool
    drop { unsafe { DROPS += 1usize } }
}
extend Guard implements Clone {
    fn clone(): Guard {
        if self.fail_clone { core.panic.panic("clone failure") }
        Guard(false)
    }
}
extend Guard implements Default {
    static fn default(): Guard {
        unsafe {
            DEFAULT_CALLS += 1usize
            if DEFAULT_CALLS == 2usize { core.panic.panic("default failure") }
        }
        Guard(false)
    }
}

fn clone_failure(): bool {
    unsafe { DROPS = 0usize }
    {
        let source = [Guard(false), Guard(true)]
        let result = catch_panic(fn(): Unit { let _ = source.clone() })
        match take result {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return false }
        }
        if unsafe { DROPS } != 1usize { return false }
    }
    unsafe { DROPS == 3usize }
}

fn default_failure(): bool {
    unsafe { DROPS = 0usize; DEFAULT_CALLS = 0usize }
    let result = catch_panic(fn(): Unit {
        let _ = [Guard; 3usize].(Default).default()
    })
    match take result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return false }
    }
    unsafe { DROPS == 1usize && DEFAULT_CALLS == 2usize }
}

fn success(): bool {
    unsafe { DROPS = 0usize; DEFAULT_CALLS = 10usize }
    {
        let source = [Guard(false), Guard(false)]
        {
            let cloned = source.clone()
            if unsafe { DROPS } != 0usize { return false }
        }
        if unsafe { DROPS } != 2usize { return false }
    }
    if unsafe { DROPS } != 4usize { return false }
    {
        let defaults = [Guard; 2usize].(Default).default()
    }
    unsafe { DROPS == 6usize && DEFAULT_CALLS == 12usize }
}

fn main(): i32 {
    if !clone_failure() { return 1 }
    if !default_failure() { return 2 }
    if !success() { return 3 }
    let empty: [Guard; 0usize] = []
    let cloned = empty.clone()
    if cloned.len() != 0usize { return 4 }
    0
}
