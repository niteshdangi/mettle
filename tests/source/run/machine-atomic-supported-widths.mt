fn main(): i32 {
    let order = core.sync.atomic.Ordering.AcqRel
    let failure_order = core.sync.atomic.Ordering.Acquire

    let i8_value = core.sync.atomic.AtomicI8.new(40i8)
    let i8_old = i8_value.fetch_add(2i8, order)
    let i8_cas = i8_value.compare_exchange(42i8, 41i8, order, failure_order)

    let u8_value = core.sync.atomic.AtomicU8.new(40u8)
    let u8_old = u8_value.fetch_add(2u8, order)
    let u8_cas = u8_value.compare_exchange(42u8, 41u8, order, failure_order)

    let i16_value = core.sync.atomic.AtomicI16.new(40i16)
    let i16_old = i16_value.fetch_add(2i16, order)
    let i16_cas = i16_value.compare_exchange(42i16, 41i16, order, failure_order)

    let u16_value = core.sync.atomic.AtomicU16.new(40u16)
    let u16_old = u16_value.fetch_add(2u16, order)
    let u16_cas = u16_value.compare_exchange(42u16, 41u16, order, failure_order)

    let i32_value = core.sync.atomic.AtomicI32.new(40i32)
    let i32_old = i32_value.fetch_add(2i32, order)
    let i32_cas = i32_value.compare_exchange(42i32, 41i32, order, failure_order)

    let u32_value = core.sync.atomic.AtomicU32.new(40u32)
    let u32_old = u32_value.fetch_add(2u32, order)
    let u32_cas = u32_value.compare_exchange(42u32, 41u32, order, failure_order)

    let i64_value = core.sync.atomic.AtomicI64.new(40i64)
    let i64_old = i64_value.fetch_add(2i64, order)
    let i64_cas = i64_value.compare_exchange(42i64, 41i64, order, failure_order)

    let u64_value = core.sync.atomic.AtomicU64.new(40u64)
    let u64_old = u64_value.fetch_add(2u64, order)
    let u64_cas = u64_value.compare_exchange(42u64, 41u64, order, failure_order)

    let isize_value = core.sync.atomic.AtomicIsize.new(40isize)
    let isize_old = isize_value.fetch_add(2isize, order)
    let isize_cas = isize_value.compare_exchange(42isize, 41isize, order, failure_order)

    let usize_value = core.sync.atomic.AtomicUsize.new(40usize)
    let usize_old = usize_value.fetch_add(2usize, order)
    let usize_cas = usize_value.compare_exchange(42usize, 41usize, order, failure_order)

    let i8_ok = match i8_cas { success(value) => value == 42i8, failure(_) => false }
    let u8_ok = match u8_cas { success(value) => value == 42u8, failure(_) => false }
    let i16_ok = match i16_cas { success(value) => value == 42i16, failure(_) => false }
    let u16_ok = match u16_cas { success(value) => value == 42u16, failure(_) => false }
    let i32_ok = match i32_cas { success(value) => value == 42i32, failure(_) => false }
    let u32_ok = match u32_cas { success(value) => value == 42u32, failure(_) => false }
    let i64_ok = match i64_cas { success(value) => value == 42i64, failure(_) => false }
    let u64_ok = match u64_cas { success(value) => value == 42u64, failure(_) => false }
    let isize_ok = match isize_cas { success(value) => value == 42isize, failure(_) => false }
    let usize_ok = match usize_cas { success(value) => value == 42usize, failure(_) => false }

    if i8_old == 40i8 && u8_old == 40u8 &&
       i16_old == 40i16 && u16_old == 40u16 &&
       i32_old == 40i32 && u32_old == 40u32 &&
       i64_old == 40i64 && u64_old == 40u64 &&
       isize_old == 40isize && usize_old == 40usize &&
       i8_ok && u8_ok && i16_ok && u16_ok && i32_ok && u32_ok &&
       i64_ok && u64_ok && isize_ok && usize_ok &&
       i8_value.load(failure_order) == 41i8 &&
       u8_value.load(failure_order) == 41u8 &&
       i16_value.load(failure_order) == 41i16 &&
       u16_value.load(failure_order) == 41u16 &&
       i32_value.load(failure_order) == 41i32 &&
       u32_value.load(failure_order) == 41u32 &&
       i64_value.load(failure_order) == 41i64 &&
       u64_value.load(failure_order) == 41u64 &&
       isize_value.load(failure_order) == 41isize &&
       usize_value.load(failure_order) == 41usize { 0 } else { 1 }
}
