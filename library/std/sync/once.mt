// Runs an initializer exactly once. A panic poisons the cell until a forced
// initializer completes successfully.
import core.panic.panic
import core.default.Default
import core.clone.Clone
import core.fmt.{Debug, Error, Formatter}

type Arm<region r> {
    state: read core.sync.atomic.AtomicU32 from r
    drop {
        let finished = if unsafe { mettle_rt_panicking() } != 0 { 3u32 } else { 2u32 }
        self.state.store(finished, core.sync.atomic.Ordering.Release)
    }
}

pub copy type OnceState { pub poisoned: bool }
extend OnceState implements Clone {
    fn clone(): OnceState { OnceState(self.poisoned) }
}
extend OnceState {
    pub fn is_poisoned(): bool { self.poisoned }
}
extend OnceState implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("OnceState")
        try debug.field("poisoned", read self.poisoned)
        try debug.finish()
    }
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

extend Once {
    pub fn is_completed(): bool { self.state.load(core.sync.atomic.Ordering.Acquire) == 2u32 }
    fn call_with<F: fn(bool): Unit>(take f: F, force: bool): Unit {
        var done = false
        while !done {
            let state = self.state.load(core.sync.atomic.Ordering.Acquire)
            if state == 2u32 {
                done = true
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
                    done = true
                }
            } else {
                unsafe { mettle_rt_thread_yield() }
            }
        }
    }

    pub fn call_once<F: fn(): Unit>(take f: F): Unit {
        self.call_with(take fn(poisoned: bool): Unit {
            if poisoned { panic("once initializer panicked") }
            f()
        }, false)
    }

    pub fn call_once_force<F: fn(OnceState): Unit>(take f: F): Unit {
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
            if state == 2u32 { return }
            unsafe { mettle_rt_thread_yield() }
        }
    }
}
extend Once implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("Once { .. }")
    }
}
