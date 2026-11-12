import package.core.clone.Clone
import package.core.convert.From
import package.core.default.Default
import package.core.fmt.{Debug, Error, Formatter}
import package.core.hash.{Hash, Hasher}

extend core.sync.atomic.Ordering implements Clone {
    fn clone(): core.sync.atomic.Ordering { self }
}
// The compiler lays Ordering out as its i32 variant index.
fn ordering_index(order: core.sync.atomic.Ordering): i32 {
    unsafe { core.mem.transmute<i32>(order) }
}
extend core.sync.atomic.Ordering implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        let index = ordering_index(self)
        if index == 0 { try f.write_str("Relaxed") }
        else if index == 1 { try f.write_str("Release") }
        else if index == 2 { try f.write_str("Acquire") }
        else if index == 3 { try f.write_str("AcqRel") }
        else { try f.write_str("SeqCst") }
    }
}
extend core.sync.atomic.Ordering implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { state.write_i32(ordering_index(self)) }
}

extend core.sync.atomic.AtomicI8 implements Default {
    static fn default(): core.sync.atomic.AtomicI8 { core.sync.atomic.AtomicI8.new(0i8) }
}
extend core.sync.atomic.AtomicI8 implements From<i8> {
    static fn from(take value: i8): core.sync.atomic.AtomicI8 { core.sync.atomic.AtomicI8.new(value) }
}
extend core.sync.atomic.AtomicI8 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try i8.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicI16 implements Default {
    static fn default(): core.sync.atomic.AtomicI16 { core.sync.atomic.AtomicI16.new(0i16) }
}
extend core.sync.atomic.AtomicI16 implements From<i16> {
    static fn from(take value: i16): core.sync.atomic.AtomicI16 { core.sync.atomic.AtomicI16.new(value) }
}
extend core.sync.atomic.AtomicI16 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try i16.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicI32 implements Default {
    static fn default(): core.sync.atomic.AtomicI32 { core.sync.atomic.AtomicI32.new(0i32) }
}
extend core.sync.atomic.AtomicI32 implements From<i32> {
    static fn from(take value: i32): core.sync.atomic.AtomicI32 { core.sync.atomic.AtomicI32.new(value) }
}
extend core.sync.atomic.AtomicI32 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try i32.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicI64 implements Default {
    static fn default(): core.sync.atomic.AtomicI64 { core.sync.atomic.AtomicI64.new(0i64) }
}
extend core.sync.atomic.AtomicI64 implements From<i64> {
    static fn from(take value: i64): core.sync.atomic.AtomicI64 { core.sync.atomic.AtomicI64.new(value) }
}
extend core.sync.atomic.AtomicI64 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try i64.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicIsize implements Default {
    static fn default(): core.sync.atomic.AtomicIsize { core.sync.atomic.AtomicIsize.new(0isize) }
}
extend core.sync.atomic.AtomicIsize implements From<isize> {
    static fn from(take value: isize): core.sync.atomic.AtomicIsize { core.sync.atomic.AtomicIsize.new(value) }
}
extend core.sync.atomic.AtomicIsize implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try isize.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicU8 implements Default {
    static fn default(): core.sync.atomic.AtomicU8 { core.sync.atomic.AtomicU8.new(0u8) }
}
extend core.sync.atomic.AtomicU8 implements From<u8> {
    static fn from(take value: u8): core.sync.atomic.AtomicU8 { core.sync.atomic.AtomicU8.new(value) }
}
extend core.sync.atomic.AtomicU8 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try u8.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicU16 implements Default {
    static fn default(): core.sync.atomic.AtomicU16 { core.sync.atomic.AtomicU16.new(0u16) }
}
extend core.sync.atomic.AtomicU16 implements From<u16> {
    static fn from(take value: u16): core.sync.atomic.AtomicU16 { core.sync.atomic.AtomicU16.new(value) }
}
extend core.sync.atomic.AtomicU16 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try u16.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicU32 implements Default {
    static fn default(): core.sync.atomic.AtomicU32 { core.sync.atomic.AtomicU32.new(0u32) }
}
extend core.sync.atomic.AtomicU32 implements From<u32> {
    static fn from(take value: u32): core.sync.atomic.AtomicU32 { core.sync.atomic.AtomicU32.new(value) }
}
extend core.sync.atomic.AtomicU32 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try u32.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicU64 implements Default {
    static fn default(): core.sync.atomic.AtomicU64 { core.sync.atomic.AtomicU64.new(0u64) }
}
extend core.sync.atomic.AtomicU64 implements From<u64> {
    static fn from(take value: u64): core.sync.atomic.AtomicU64 { core.sync.atomic.AtomicU64.new(value) }
}
extend core.sync.atomic.AtomicU64 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try u64.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicUsize implements Default {
    static fn default(): core.sync.atomic.AtomicUsize { core.sync.atomic.AtomicUsize.new(0usize) }
}
extend core.sync.atomic.AtomicUsize implements From<usize> {
    static fn from(take value: usize): core.sync.atomic.AtomicUsize { core.sync.atomic.AtomicUsize.new(value) }
}
extend core.sync.atomic.AtomicUsize implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try usize.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicBool implements Default {
    static fn default(): core.sync.atomic.AtomicBool { core.sync.atomic.AtomicBool.new(false) }
}
extend core.sync.atomic.AtomicBool implements From<bool> {
    static fn from(take value: bool): core.sync.atomic.AtomicBool { core.sync.atomic.AtomicBool.new(value) }
}
extend core.sync.atomic.AtomicBool implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try bool.(Debug).fmt(self.load(core.sync.atomic.Ordering.Relaxed), mut f)
    }
}

extend core.sync.atomic.AtomicI8 {
    pub fn fetch_update<F: mut fn(i8): (i8)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<i8, i8> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicI16 {
    pub fn fetch_update<F: mut fn(i16): (i16)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<i16, i16> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicI32 {
    pub fn fetch_update<F: mut fn(i32): (i32)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<i32, i32> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicI64 {
    pub fn fetch_update<F: mut fn(i64): (i64)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<i64, i64> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicIsize {
    pub fn fetch_update<F: mut fn(isize): (isize)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<isize, isize> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicU8 {
    pub fn fetch_update<F: mut fn(u8): (u8)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<u8, u8> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicU16 {
    pub fn fetch_update<F: mut fn(u16): (u16)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<u16, u16> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicU32 {
    pub fn fetch_update<F: mut fn(u32): (u32)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<u32, u32> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicU64 {
    pub fn fetch_update<F: mut fn(u64): (u64)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<u64, u64> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicUsize {
    pub fn fetch_update<F: mut fn(usize): (usize)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<usize, usize> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend core.sync.atomic.AtomicBool {
    pub fn fetch_update<F: mut fn(bool): (bool)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<bool, bool> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}

extend<T> core.sync.atomic.AtomicPtr<T> {
    pub fn fetch_update<F: mut fn(ptr<mut T>): (ptr<mut T>)?>(set_order: core.sync.atomic.Ordering, fetch_order: core.sync.atomic.Ordering, take f: F): Outcome<ptr<mut T>, ptr<mut T>> {
        var callback = f
        var current = self.load(fetch_order)
        loop {
            match callback(current) {
                present(next) => match self.compare_exchange_weak(current, next, set_order, fetch_order) {
                    success(old) => { return success(old) },
                    failure(seen) => { current = seen }
                },
                none => { return failure(current) }
            }
        }
    }
}
