import core.default.Default
import core.fmt.{Debug, Error, Formatter}
import core.ops.{Deref, DerefMut}
import super.once
import super.once.Once

pub type LazyLock<T, F = fn(): T> {
    once: Once
    value: core.cell.UnsafeCell<core.mem.MaybeUninit<T>>
    initializer: core.cell.UnsafeCell<F?>
    drop {
        if self.once.is_completed() {
            // Safety: Once completes only after the initialized value is published.
            unsafe { core.ptr.drop_in_place(self.value.get().cast<T>()) }
        }
    }
}

// Once serializes the initializer and publishes the completed value.
unsafe extend<T: Transferable, F: Transferable> LazyLock<T, F>
    implements Transferable {}
unsafe extend<T: Transferable + Shareable, F: Transferable> LazyLock<T, F>
    implements Shareable {}
unsafe extend<T: RefUnwindSafe + UnwindSafe, F: UnwindSafe>
    std.sync.lazy_lock.LazyLock<T, F> implements RefUnwindSafe {}

extend<T, F: take fn(): T> LazyLock<T, F> {
    pub static const fn new(take initializer: F): LazyLock<T, F> {
        LazyLock(
            once.new(),
            core.cell.UnsafeCell.new(core.mem.MaybeUninit<T>.uninit()),
            core.cell.UnsafeCell.new(present(initializer))
        )
    }
}

extend<T, F> LazyLock<T, F> {
    pub fn get(): (read T from self)? {
        if !self.once.is_completed() { return none }
        // Safety: Once's acquire load observes the value written before completion.
        present(unsafe { read *self.value.get().cast<T>() })
    }

    pub mut fn get_mut(): (mut T from self)? {
        if !self.once.is_completed() { return none }
        // Safety: the mutable receiver is exclusive and Once confirms initialization.
        present(unsafe { mut *self.value.get().cast<T>() })
    }
}

extend<T, F: take fn(): T> LazyLock<T, F> {
    // Called only by Once's winning initializer; it consumes F once and publishes T.
    unsafe fn initialize(): Unit {
        let pointer = self.initializer.get()
        let stored = unsafe { core.ptr.`read`(pointer) }
        unsafe { core.ptr.write(pointer, none) }
        let initializer = match take stored {
            present(initializer) => initializer,
            none => core.intrinsics.abort()
        }
        let value = initializer()
        unsafe {
            core.ptr.write(
                self.value.get(),
                core.mem.MaybeUninit.new(value)
            )
        }
    }

    pub fn force(): read T from self {
        self.once.call_once(fn(): Unit { unsafe { self.initialize() } })
        // Safety: successful return from call_once follows value publication.
        unsafe { read *self.value.get().cast<T>() }
    }

    pub mut fn force_mut(): mut T from self {
        self.once.call_once(fn(): Unit { unsafe { self.initialize() } })
        // Safety: the mutable receiver is exclusive and call_once completed.
        unsafe { mut *self.value.get().cast<T>() }
    }
}

extend<T: Default> LazyLock<T> implements Default {
    static fn default(): LazyLock<T> {
        LazyLock<T>.new(fn(): T { T.(Default).default() })
    }
}

extend<T, F> LazyLock<T, F> implements core.convert.From<T> {
    static fn from(take value: T): LazyLock<T, F> {
        var result: LazyLock<T, F> = LazyLock<T, F>(
            once.new(),
            core.cell.UnsafeCell<core.mem.MaybeUninit<T>>.new(
                core.mem.MaybeUninit<T>.new(value)
            ),
            core.cell.UnsafeCell<F?>.new(none)
        )
        result.once.call_once(fn(): Unit {})
        result
    }
}

extend<T: Debug, F> LazyLock<T, F> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("LazyLock(")
        match self.get() {
            present(value) => try T.(Debug).fmt(value, mut f),
            none => try f.write_str("<uninit>")
        }
        try f.write_str(")")
    }
}

extend<T, F: take fn(): T> LazyLock<T, F> implements Deref {
    type Target = T
    fn deref(): read T from self { self.force() }
}

extend<T, F: take fn(): T> LazyLock<T, F> implements DerefMut {
    mut fn deref_mut(): mut T from self { self.force_mut() }
}
