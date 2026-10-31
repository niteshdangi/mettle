// Runs an initializer exactly once. A panic poisons the cell until a forced
// initializer completes successfully.
import package.core.panic.panic
import package.core.default.Default
import package.core.fmt

type Arm<region r> {
    state: read core.sync.atomic.AtomicU32 from r
    drop {
        let finished = if unsafe { mettle_rt_panicking() } != 0 { 3u32 } else { 2u32 }
        self.state.store(finished, core.sync.atomic.Ordering.Release)
    }
}

pub copy type OnceState { pub poisoned: bool }
extend OnceState {
    pub fn is_poisoned(): bool { self.poisoned }
}

extern "C" {
    unsafe fn mettle_rt_panicking(): i32;
    unsafe fn mettle_rt_thread_yield(): Unit;
}

pub type Once {
    state: core.sync.atomic.AtomicU32
}
unsafe extend Once implements Transferable {}
unsafe extend Once implements Shareable {}

pub fn new(): Once { Once(core.sync.atomic.AtomicU32.new(0u32)) }
extend Once implements Default {
    static fn default(): Once { new() }
}
extend Once implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Once")
        try fields.field("completed", self.is_completed())
        try fields.finish()
    }
}

extend Once {
    pub fn is_completed(): bool { self.state.load(core.sync.atomic.Ordering.Acquire) == 2u32 }
    fn call_with<F: take fn(bool): Unit>(f: take F, force: bool): Unit {
        while true {
            let state = self.state.load(core.sync.atomic.Ordering.Acquire)
            if state == 2u32 {
                return
            } else if state == 3u32 && !force {
                panic("once initializer panicked")
            } else if state == 0u32 || state == 3u32 {
                let seen = self.state.compare_exchange(
                    state, 1u32, core.sync.atomic.Ordering.AcqRel,
                    core.sync.atomic.Ordering.Acquire
                )
                if seen.is_failure() {
                    unsafe { mettle_rt_thread_yield() }
                } else {
                    let arm = Arm(read self.state)
                    f(state == 3u32)
                    return
                }
            } else {
                unsafe { mettle_rt_thread_yield() }
            }
        }
    }

    pub fn call_once<F: take fn(): Unit>(f: take F): Unit {
        self.call_with(take fn(poisoned: bool): Unit {
            if poisoned { panic("once initializer panicked") }
            f()
        }, false)
    }

    pub fn call_once_force<F: take fn(OnceState): Unit>(f: take F): Unit {
        self.call_with(take fn(poisoned: bool): Unit { f(OnceState(poisoned)) }, true)
    }

    pub fn wait(): Unit {
        while !self.is_completed() {
            if self.state.load(core.sync.atomic.Ordering.Acquire) == 3u32 {
                panic("once initializer panicked")
            }
            unsafe { mettle_rt_thread_yield() }
        }
    }

    pub fn wait_force(): Unit {
        while true {
            let state = self.state.load(core.sync.atomic.Ordering.Acquire)
            if state == 2u32 || state == 3u32 { return }
            unsafe { mettle_rt_thread_yield() }
        }
    }
}
