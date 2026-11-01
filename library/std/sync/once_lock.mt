// A value initialized at most once, with readers waiting only during init.
import package.core.panic.panic
import package.core.default.Default
import package.core.clone.Clone
import package.core.cmp.{Eq, PartialEq}
import package.core.convert.From
import package.core.fmt.{Debug, Error, Formatter}

extern "C" {
    unsafe fn mettle_rt_thread_yield(): Unit;
}

type InitGuard<region r> {
    state: read core.sync.atomic.AtomicU32 from r
    initialized: bool
    drop {
        self.state.store(
            if self.initialized { 2u32 } else { 0u32 },
            core.sync.atomic.Ordering.Release
        )
    }
}

pub type SetError<T> { pub value: T }
extend<T> SetError<T> {
    pub take fn into_inner(): T { self.value }
}

pub type OnceLock<T> {
    state: core.sync.atomic.AtomicU32
    value: core.cell.UnsafeCell<core.mem.MaybeUninit<T>>
    drop {
        if self.state.load(core.sync.atomic.Ordering.Relaxed) == 2u32 {
            unsafe { core.ptr.drop_in_place(self.value.get().cast<T>()) }
        }
    }
}
unsafe extend<T: Transferable> OnceLock<T> implements Transferable {}
unsafe extend<T: Transferable + Shareable> OnceLock<T> implements Shareable {}

pub fn new<T>(): OnceLock<T> {
    OnceLock(
        core.sync.atomic.AtomicU32.new(0u32),
        core.cell.UnsafeCell.new(core.mem.MaybeUninit<T>.uninit())
    )
}
extend<T> OnceLock<T> implements From<T> {
    static fn `from`(value: take T): OnceLock<T> {
        // The initialized state and payload are constructed before the cell escapes.
        OnceLock(
            core.sync.atomic.AtomicU32.new(2u32),
            core.cell.UnsafeCell.new(core.mem.MaybeUninit.new(value))
        )
    }
}
extend<T> OnceLock<T> implements Default {
    static fn default(): OnceLock<T> { new<T>() }
}
extend<T: Clone> OnceLock<T> implements Clone {
    fn clone(): OnceLock<T> {
        let copied = new<T>()
        match self.get() {
            present(value) => {
                let result = capture copied.set(value.clone())
                match take result {
                    success(_) => copied,
                    failure(error) => { core.intrinsics.abort() }
                }
            },
            none => copied
        }
    }
}
extend<T: PartialEq> OnceLock<T> implements PartialEq {
    fn eq(other: read OnceLock<T>): bool {
        match self.get() {
            present(left) => match other.get() {
                present(right) => left == right,
                none => false
            },
            none => match other.get() {
                present(value) => false,
                none => true
            }
        }
    }
}
extend<T: Eq> OnceLock<T> implements Eq {}
extend<T: Debug> OnceLock<T> implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("OnceLock(")
        match self.get() {
            present(value) => try T.(Debug).fmt(value, mut f),
            none => try f.write_str("<uninit>")
        }
        try f.write_str(")")
    }
}

extend<T> OnceLock<T> {
    pub fn get(): (read T from self)? {
        if self.state.load(core.sync.atomic.Ordering.Acquire) == 2u32 {
            present(unsafe { read *self.value.get().cast<T>() })
        } else {
            none
        }
    }

    pub mut fn get_mut(): (mut T from self)? {
        if self.state.load(core.sync.atomic.Ordering.Relaxed) == 2u32 {
            present(unsafe { mut *self.value.get().cast<T>() })
        } else {
            none
        }
    }

    pub fn set(value: take T): Unit throws SetError<T> {
        while true {
            let state = self.state.load(core.sync.atomic.Ordering.Acquire)
            if state == 2u32 { throw SetError(value) }
            if state == 0u32 {
                let changed = self.state.compare_exchange(
                    0u32, 1u32, core.sync.atomic.Ordering.AcqRel,
                    core.sync.atomic.Ordering.Acquire
                )
                if changed.is_failure() { continue }
                unsafe {
                    core.ptr.write(
                        self.value.get(), core.mem.MaybeUninit.new(value)
                    )
                }
                self.state.store(2u32, core.sync.atomic.Ordering.Release)
                return
            }
            unsafe { mettle_rt_thread_yield() }
        }
    }

    pub fn get_or_init<F: fn(): T>(initializer: take F): read T from self {
        while true {
            let state = self.state.load(core.sync.atomic.Ordering.Acquire)
            if state == 2u32 {
                match self.get() {
                    present(value) => { return value },
                    none => { core.intrinsics.abort() }
                }
            }
            if state == 0u32 {
                let changed = self.state.compare_exchange(
                    0u32, 1u32, core.sync.atomic.Ordering.AcqRel,
                    core.sync.atomic.Ordering.Acquire
                )
                if changed.is_failure() { continue }
                var guard = InitGuard(read self.state, false)
                let value = initializer()
                unsafe {
                    core.ptr.write(
                        self.value.get(), core.mem.MaybeUninit.new(value)
                    )
                }
                guard.initialized = true
                return unsafe { read *self.value.get().cast<T>() }
            }
            unsafe { mettle_rt_thread_yield() }
        }
        core.intrinsics.abort()
    }

    pub fn wait(): read T from self {
        while self.state.load(core.sync.atomic.Ordering.Acquire) != 2u32 {
            unsafe { mettle_rt_thread_yield() }
        }
        unsafe { read *self.value.get().cast<T>() }
    }

    pub mut fn `take`(): T? {
        if self.state.load(core.sync.atomic.Ordering.Relaxed) != 2u32 {
            return none
        }
        self.state.store(0u32, core.sync.atomic.Ordering.Relaxed)
        present(unsafe { core.ptr.`read`(self.value.get().cast<T>()) })
    }

    pub take fn into_inner(): T? {
        if self.state.load(core.sync.atomic.Ordering.Relaxed) != 2u32 {
            return none
        }
        self.state.store(0u32, core.sync.atomic.Ordering.Relaxed)
        present(unsafe { core.ptr.`read`(self.value.get().cast<T>()) })
    }
}
