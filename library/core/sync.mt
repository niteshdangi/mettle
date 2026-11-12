import package.core.clone.Clone
import package.core.convert.From
import package.core.default.Default
import package.core.fmt.{Debug, Error, Formatter}

extend core.sync.atomic.Ordering implements Clone {
    fn clone(): core.sync.atomic.Ordering { self }
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
