import core.clone.Clone
import core.convert.From
import core.default.Default
import core.fmt
import core.fmt.Debug

fn default_value<T: Default>(): T { T.(Default).default() }
fn from_value<T: From<V>, V>(take value: V): T { T.(From<V>).from(value) }
fn debug_is<T: Debug>(read value: T, read expected: core.text.Text): bool {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { return false }
        }
    }
    output.as_text() == expected
}

fn main(): i32 {
    let relaxed = core.sync.atomic.Ordering.Relaxed
    let i8_default: core.sync.atomic.AtomicI8 = default_value<core.sync.atomic.AtomicI8>()
    let i8_from: core.sync.atomic.AtomicI8 = from_value<core.sync.atomic.AtomicI8, i8>(7i8)
    if i8_default.load(relaxed) != 0i8 || i8_from.load(relaxed) != 7i8 { return 1 }
    if !debug_is(read i8_from, "7") { return 2 }
    let i16_default: core.sync.atomic.AtomicI16 = default_value<core.sync.atomic.AtomicI16>()
    let i16_from: core.sync.atomic.AtomicI16 = from_value<core.sync.atomic.AtomicI16, i16>(7i16)
    if i16_default.load(relaxed) != 0i16 || i16_from.load(relaxed) != 7i16 { return 11 }
    if !debug_is(read i16_from, "7") { return 12 }
    let i32_default: core.sync.atomic.AtomicI32 = default_value<core.sync.atomic.AtomicI32>()
    let i32_from: core.sync.atomic.AtomicI32 = from_value<core.sync.atomic.AtomicI32, i32>(7i32)
    if i32_default.load(relaxed) != 0i32 || i32_from.load(relaxed) != 7i32 { return 21 }
    if !debug_is(read i32_from, "7") { return 22 }
    let i64_default: core.sync.atomic.AtomicI64 = default_value<core.sync.atomic.AtomicI64>()
    let i64_from: core.sync.atomic.AtomicI64 = from_value<core.sync.atomic.AtomicI64, i64>(7i64)
    if i64_default.load(relaxed) != 0i64 || i64_from.load(relaxed) != 7i64 { return 31 }
    if !debug_is(read i64_from, "7") { return 32 }
    let isize_default: core.sync.atomic.AtomicIsize = default_value<core.sync.atomic.AtomicIsize>()
    let isize_from: core.sync.atomic.AtomicIsize = from_value<core.sync.atomic.AtomicIsize, isize>(7isize)
    if isize_default.load(relaxed) != 0isize || isize_from.load(relaxed) != 7isize { return 41 }
    if !debug_is(read isize_from, "7") { return 42 }
    let u8_default: core.sync.atomic.AtomicU8 = default_value<core.sync.atomic.AtomicU8>()
    let u8_from: core.sync.atomic.AtomicU8 = from_value<core.sync.atomic.AtomicU8, u8>(7u8)
    if u8_default.load(relaxed) != 0u8 || u8_from.load(relaxed) != 7u8 { return 51 }
    if !debug_is(read u8_from, "7") { return 52 }
    let u16_default: core.sync.atomic.AtomicU16 = default_value<core.sync.atomic.AtomicU16>()
    let u16_from: core.sync.atomic.AtomicU16 = from_value<core.sync.atomic.AtomicU16, u16>(7u16)
    if u16_default.load(relaxed) != 0u16 || u16_from.load(relaxed) != 7u16 { return 61 }
    if !debug_is(read u16_from, "7") { return 62 }
    let u32_default: core.sync.atomic.AtomicU32 = default_value<core.sync.atomic.AtomicU32>()
    let u32_from: core.sync.atomic.AtomicU32 = from_value<core.sync.atomic.AtomicU32, u32>(7u32)
    if u32_default.load(relaxed) != 0u32 || u32_from.load(relaxed) != 7u32 { return 71 }
    if !debug_is(read u32_from, "7") { return 72 }
    let u64_default: core.sync.atomic.AtomicU64 = default_value<core.sync.atomic.AtomicU64>()
    let u64_from: core.sync.atomic.AtomicU64 = from_value<core.sync.atomic.AtomicU64, u64>(7u64)
    if u64_default.load(relaxed) != 0u64 || u64_from.load(relaxed) != 7u64 { return 81 }
    if !debug_is(read u64_from, "7") { return 82 }
    let usize_default: core.sync.atomic.AtomicUsize = default_value<core.sync.atomic.AtomicUsize>()
    let usize_from: core.sync.atomic.AtomicUsize = from_value<core.sync.atomic.AtomicUsize, usize>(7usize)
    if usize_default.load(relaxed) != 0usize || usize_from.load(relaxed) != 7usize { return 91 }
    if !debug_is(read usize_from, "7") { return 92 }
    let flag_default: core.sync.atomic.AtomicBool = default_value<core.sync.atomic.AtomicBool>()
    let flag_from: core.sync.atomic.AtomicBool = from_value<core.sync.atomic.AtomicBool, bool>(true)
    if flag_default.load(relaxed) || !flag_from.load(relaxed) { return 101 }
    if !debug_is(read flag_from, "true") { return 102 }
    let original = core.sync.atomic.Ordering.SeqCst
    let cloned = core.sync.atomic.Ordering.(Clone).clone(read original)
    core.sync.atomic.fence(cloned)
    0
}
