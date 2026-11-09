// expect-exit: 0
// profiles: debug release

import core.any
import core.any.{Any, TypeId}
import core.borrow.{Borrow, ToOwned}
import core.cmp.{Ordering, PartialEq, PartialOrd}
import core.clone.Clone
import core.convert.{From, Into, TryFrom, TryInto}
import core.default.Default
import core.float
import core.iter
import core.iter.{Iterator, Product, Sum}

fn copy_pair<T: Copy>(value: T): (T, T) { (value, value) }

fn require_float_markers<T: Copy + Transferable + Shareable>(value: T) {}

fn erased_type(read value: any Any): TypeId { value.type_id() }

fn equal_f32(read left: f32, read right: f32): bool {
    f32.(PartialEq<f32>).eq(left, right)
}

fn equal_f64(read left: f64, read right: f64): bool {
    f64.(PartialEq<f64>).eq(left, right)
}

fn less_f32(read left: f32, read right: f32): bool {
    match f32.(PartialOrd<f32>).partial_cmp(left, right) {
        present(Ordering.Less) => true,
        _ => false
    }
}

fn less_f64(read left: f64, read right: f64): bool {
    match f64.(PartialOrd<f64>).partial_cmp(left, right) {
        present(Ordering.Less) => true,
        _ => false
    }
}

fn equal_order_f32(read left: f32, read right: f32): bool {
    match f32.(PartialOrd<f32>).partial_cmp(left, right) {
        present(Ordering.Equal) => true,
        _ => false
    }
}

fn equal_order_f64(read left: f64, read right: f64): bool {
    match f64.(PartialOrd<f64>).partial_cmp(left, right) {
        present(Ordering.Equal) => true,
        _ => false
    }
}

fn unordered_f32(read left: f32, read right: f32): bool {
    match f32.(PartialOrd<f32>).partial_cmp(left, right) {
        none => true,
        _ => false
    }
}

fn unordered_f64(read left: f64, read right: f64): bool {
    match f64.(PartialOrd<f64>).partial_cmp(left, right) {
        none => true,
        _ => false
    }
}

fn main(): i32 {
    let nan32 = f32.from_bits(0x7fc12345u32)
    let nan64 = f64.from_bits(0x7ff8123456789abcu64)
    let negative_zero32 = f32.from_bits(0x80000000u32)
    let negative_zero64 = f64.from_bits(0x8000000000000000u64)

    require_float_markers(nan32)
    require_float_markers(nan64)

    let (copy32_a, copy32_b) = copy_pair(nan32)
    let (copy64_a, copy64_b) = copy_pair(nan64)
    let cloned32 = nan32.clone()
    let cloned64 = nan64.clone()
    var clone_target32 = 0.0f32
    var clone_target64 = 0.0f64
    clone_target32.clone_from(read nan32)
    clone_target64.clone_from(read nan64)
    let borrowed32 = nan32.borrow()
    let borrowed64 = nan64.borrow()
    let owned32 = borrowed32.to_owned()
    let owned64 = borrowed64.to_owned()
    var clone_into32 = 0.0f32
    var clone_into64 = 0.0f64
    borrowed32.clone_into(mut clone_into32)
    borrowed64.clone_into(mut clone_into64)
    if copy32_a.to_bits() != 0x7fc12345u32 ||
       copy32_b.to_bits() != 0x7fc12345u32 ||
       cloned32.to_bits() != 0x7fc12345u32 ||
       clone_target32.to_bits() != 0x7fc12345u32 ||
       borrowed32.to_bits() != 0x7fc12345u32 ||
       owned32.to_bits() != 0x7fc12345u32 ||
       clone_into32.to_bits() != 0x7fc12345u32 {
        return 1
    }
    if copy64_a.to_bits() != 0x7ff8123456789abcu64 ||
       copy64_b.to_bits() != 0x7ff8123456789abcu64 ||
       cloned64.to_bits() != 0x7ff8123456789abcu64 ||
       clone_target64.to_bits() != 0x7ff8123456789abcu64 ||
       borrowed64.to_bits() != 0x7ff8123456789abcu64 ||
       owned64.to_bits() != 0x7ff8123456789abcu64 ||
       clone_into64.to_bits() != 0x7ff8123456789abcu64 {
        return 2
    }

    if f32.(Default).default().to_bits() != 0u32 ||
       f64.(Default).default().to_bits() != 0u64 {
        return 3
    }

    let from32 = f32.(From<f32>).from(nan32.clone())
    let from64 = f64.(From<f64>).from(nan64.clone())
    let into32: f32 = f32.(Into<f32>).into(nan32.clone())
    let into64: f64 = f64.(Into<f64>).into(nan64.clone())
    let try_from32: (Outcome<f32, Never>) = f32.(TryFrom<f32>).try_from(nan32.clone())
    let try_from64: (Outcome<f64, Never>) = f64.(TryFrom<f64>).try_from(nan64.clone())
    let try_into32: (Outcome<f32, Never>) = f32.(TryInto<f32>).try_into(nan32.clone())
    let try_into64: (Outcome<f64, Never>) = f64.(TryInto<f64>).try_into(nan64.clone())
    if from32.to_bits() != 0x7fc12345u32 ||
       from64.to_bits() != 0x7ff8123456789abcu64 ||
       into32.to_bits() != 0x7fc12345u32 ||
       into64.to_bits() != 0x7ff8123456789abcu64 {
        return 4
    }
    match try_from32 {
        success(value) => { if value.to_bits() != 0x7fc12345u32 { return 5 } }
    }
    match try_from64 {
        success(value) => { if value.to_bits() != 0x7ff8123456789abcu64 { return 6 } }
    }
    match try_into32 {
        success(value) => { if value.to_bits() != 0x7fc12345u32 { return 7 } }
    }
    match try_into64 {
        success(value) => { if value.to_bits() != 0x7ff8123456789abcu64 { return 8 } }
    }

    if !equal_f32(0.0f32, negative_zero32) ||
       !equal_f64(0.0f64, negative_zero64) ||
       !equal_order_f32(0.0f32, negative_zero32) ||
       !equal_order_f64(0.0f64, negative_zero64) ||
       equal_f32(nan32, nan32) || equal_f64(nan64, nan64) ||
       !less_f32(-1.0f32, 0.0f32) || !less_f64(-1.0f64, 0.0f64) ||
       !unordered_f32(nan32, 0.0f32) || !unordered_f64(nan64, 0.0f64) {
        return 9
    }

    if erased_type(read nan32) != any.type_id<f32>() ||
       erased_type(read nan64) != any.type_id<f64>() {
        return 10
    }
    match any.downcast_ref<f32>(read nan32) {
        present(value) => { if value.to_bits() != 0x7fc12345u32 { return 11 } },
        none => { return 11 }
    }
    match any.downcast_ref<f64>(read nan64) {
        present(value) => { if value.to_bits() != 0x7ff8123456789abcu64 { return 12 } },
        none => { return 12 }
    }
    match any.downcast_ref<f64>(read nan32) {
        present(_) => { return 13 },
        none => {}
    }
    match any.downcast_ref<f32>(read nan64) {
        present(_) => { return 14 },
        none => {}
    }

    let empty32: [f32; 0] = []
    let empty64: [f64; 0] = []
    if empty32.iter().copied().sum<f32>().to_bits() != 0u32 ||
       empty32.iter().copied().product<f32>() != 1.0f32 ||
       empty64.iter().copied().sum<f64>().to_bits() != 0u64 ||
       empty64.iter().copied().product<f64>() != 1.0f64 {
        return 15
    }

    let values32 = [1.0f32, 2.0f32, 3.0f32]
    let values64 = [1.0f64, 2.0f64, 3.0f64]
    if values32.iter().copied().sum<f32>() != 6.0f32 ||
       values32.iter().copied().product<f32>() != 6.0f32 ||
       values64.iter().copied().sum<f64>() != 6.0f64 ||
       values64.iter().copied().product<f64>() != 6.0f64 ||
       values32[0usize] != 1.0f32 || values64[2usize] != 3.0f64 {
        return 16
    }

    let signed_product32 = [negative_zero32, 2.0f32].iter().copied().product<f32>()
    let signed_product64 = [negative_zero64, 2.0f64].iter().copied().product<f64>()
    if signed_product32.to_bits() != 0x80000000u32 ||
       signed_product64.to_bits() != 0x8000000000000000u64 ||
       ![nan32, 1.0f32].iter().copied().sum<f32>().is_nan() ||
       ![nan64, 1.0f64].iter().copied().product<f64>().is_nan() {
        return 17
    }

    let owned_sum32: f32 = iter.sum(iter.once(2.5f32))
    let owned_product64: f64 = iter.product(iter.once(2.5f64))
    if owned_sum32 != 2.5f32 || owned_product64 != 2.5f64 {
        return 18
    }

    if 1.5f32 + 2.25f32 != 3.75f32 ||
       5.5f32 - 2.25f32 != 3.25f32 ||
       2.5f32 * 2.0f32 != 5.0f32 ||
       5.0f32 / 2.0f32 != 2.5f32 ||
       5.5f32 % 2.0f32 != 1.5f32 ||
       1.5f64 + 2.25f64 != 3.75f64 ||
       5.5f64 - 2.25f64 != 3.25f64 ||
       2.5f64 * 2.0f64 != 5.0f64 ||
       5.0f64 / 2.0f64 != 2.5f64 ||
       5.5f64 % 2.0f64 != 1.5f64 ||
       (-negative_zero32).to_bits() != 0u32 ||
       (-negative_zero64).to_bits() != 0u64 {
        return 19
    }
    if 9.0f32.sqrt() != 3.0f32 ||
       25.0f64.sqrt() != 5.0f64 ||
       !(-1.0f32).sqrt().is_nan() ||
       !(-1.0f64).sqrt().is_nan() {
        return 20
    }

    0
}
