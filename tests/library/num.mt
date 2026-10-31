import core.num
import core.convert.TryFrom
import core.num.IntErrorKind
import core.option
import core.ops
import core.fmt
import core.fmt.Debug
import core.fmt.Display

fn debug_matches<T: Debug>(value: read T, expected: read core.text.Text): bool {
      var bytes = [0u8; 64]
      let length = {
            var writer = fmt.buffer_writer(mut bytes)
            var formatter = fmt.formatter(mut writer, fmt.spec())
            match capture T.(Debug).fmt(value, mut formatter) {
                success(unit) => {},
                failure(error) => { return false }
            }
            writer.len()
      }
      match fmt.written_text(read bytes, length) {
            present(text) => text == expected,
            none => false
      }
}

fn display_matches<T: Display>(value: read T, expected: read core.text.Text): bool {
      var bytes = [0u8; 64]
      let length = {
            var writer = fmt.buffer_writer(mut bytes)
            var formatter = fmt.formatter(mut writer, fmt.spec())
            match capture T.(Display).fmt(value, mut formatter) {
                success(unit) => {},
                failure(error) => { return false }
            }
            writer.len()
      }
      match fmt.written_text(read bytes, length) {
            present(text) => text == expected,
            none => false
      }
}

fn check_wrapping<W: Copy + core.cmp.PartialEq +
      ops.Add<W, Output = W> + ops.Sub<W, Output = W> +
      ops.Mul<W, Output = W> + ops.Div<W, Output = W> +
      ops.Rem<W, Output = W> + ops.BitAnd<W, Output = W> +
      ops.BitOr<W, Output = W> + ops.BitXor<W, Output = W> +
      ops.Shl<u32, Output = W> + ops.Shr<u32, Output = W> +
      ops.Neg<Output = W> + ops.Not<Output = W>>(
      left: take W, right: take W,
      sum: take W, difference: take W, product: take W,
      quotient: take W, remainder: take W,
      bitand: take W, bitor: take W, bitxor: take W,
      negated: take W, inverted: take W, shifted_left: take W, shifted_right: take W
): bool {
      left + right == sum && left - right == difference && left * right == product &&
            left / right == quotient && left % right == remainder &&
            left & right == bitand && left | right == bitor && left ^ right == bitxor &&
            -left == negated && !left == inverted &&
            left << 1u32 == shifted_left && left >> 1u32 == shifted_right
}

fn check_wrapping_overflow<W: Copy + core.cmp.PartialEq +
      ops.Add<W, Output = W> + ops.Sub<W, Output = W> + ops.Mul<W, Output = W>>(
      maximum: take W, zero: take W, one: take W, two: take W,
      wrapped_sum: take W, wrapped_sub: take W, wrapped_product: take W
): bool {
      maximum + one == wrapped_sum && zero - one == wrapped_sub &&
            maximum * two == wrapped_product
}

fn check_wrapping_assign<W: Copy + core.cmp.PartialEq +
      ops.AddAssign<W> + ops.SubAssign<W> + ops.MulAssign<W> +
      ops.DivAssign<W> + ops.RemAssign<W> + ops.BitAndAssign<W> +
      ops.BitOrAssign<W> + ops.BitXorAssign<W> +
      ops.ShlAssign<u32> + ops.ShrAssign<u32>>(
      left: take W, right: take W, expected_sum: take W,
      expected_difference: take W, expected_product: take W,
      expected_quotient: take W, expected_remainder: take W,
      expected_and: take W, expected_or: take W, expected_xor: take W,
      expected_left: take W, expected_right: take W
): bool {
      var value = left
      value += right
      if value != expected_sum { return false }
      value = left
      value -= right
      if value != expected_difference { return false }
      value = left
      value *= right
      if value != expected_product { return false }
      value = left
      value /= right
      if value != expected_quotient { return false }
      value = left
      value %= right
      if value != expected_remainder { return false }
      value = left
      value &= right
      if value != expected_and { return false }
      value = left
      value |= right
      if value != expected_or { return false }
      value = left
      value ^= right
      if value != expected_xor { return false }
      value = left
      value <<= 1u32
      if value != expected_left { return false }
      value = left
      value >>= 1u32
      value == expected_right
}

fn check_wrapping_shift_edges<W: Copy + core.cmp.PartialEq +
      ops.Shl<u32, Output = W> + ops.Shr<u32, Output = W> +
      ops.ShlAssign<u32> + ops.ShrAssign<u32>>(
      one: take W, width: u32, width_plus_one: u32, large_count: u32,
      zero: take W, one_after_width: take W, two_after_width: take W, high_bit: take W
): bool {
      let shifted_width = one << width
      let shifted_width_plus_one = one << width_plus_one
      let shifted_large = one << large_count
      let right_width = one >> width
      let right_width_plus_one = one >> width_plus_one
      if shifted_width != one_after_width || shifted_width_plus_one != two_after_width ||
            shifted_large != high_bit || right_width != one || right_width_plus_one != zero {
            return false
      }
      var assign = one
      assign <<= large_count
      if assign != high_bit { return false }
      assign = one
      assign >>= width
      assign == one
}

fn check_wrapping_signed_div_edges<W: Copy + core.cmp.PartialEq +
      ops.Div<W, Output = W> + ops.Rem<W, Output = W> +
      ops.DivAssign<W> + ops.RemAssign<W>>(
      minimum: take W, negative_one: take W, zero: take W
): bool {
      if minimum / negative_one != minimum || minimum % negative_one != zero { return false }
      var value = minimum
      value /= negative_one
      if value != minimum { return false }
      value = minimum
      value %= negative_one
      value == zero
}

fn kind<T: num.FromText>(text: read core.text.Text): IntErrorKind? {
      match capture num.parse<T>(text) { success(v) => none, failure(e) => present(e.kind) }
}
fn check_integer_operation_gaps(): i32 {
      if 40u8.bit_width() != 6u32 { return 1 }
      match 40u8.highest_one() { present(position) => { if position != 5u32 { return 2 } }, none => { return 3 } }
      match 40u8.lowest_one() { present(position) => { if position != 3u32 { return 4 } }, none => { return 5 } }
      if 40u8.isolate_highest_one() != 32u8 || 40u8.isolate_lowest_one() != 8u8 { return 6 }
      match 3u8.checked_signed_diff(5u8) { present(diff) => { if diff != -2i8 { return 7 } }, none => { return 8 } }
      let (sum, carry) = 255u8.carrying_add(0u8, true)
      if sum != 0u8 || !carry { return 9 }
      let (difference, borrow) = 0u8.borrowing_sub(0u8, true)
      if difference != 255u8 || !borrow { return 10 }
      let (low, high) = 200u8.carrying_mul(100u8, 7u8)
      if low != 0x27u8 || high != 0x4eu8 { return 11 }
      match u8.(TryFrom<i32>).try_from(256i32) { success(v) => { return 12 }, failure(e) => {} }
      match u8.(TryFrom<i32>).try_from(255i32) { success(v) => { if v != 255u8 { return 13 } }, failure(e) => { return 14 } }
      if f64.EPSILON != 1.0f64.next_up() - 1.0f64 { return 15 }
      if u16.BITS != 16u32 { return 16 }
      if (-5i32).abs() != 5i32 || 7i8.abs() != 7i8 || (-127i8).abs() != 127i8 { return 17 }
      0
}

fn main(): i32 {
    if num.Wrapping(1u8) << 8u8 != num.Wrapping(1u8) ||
          num.Wrapping(1u8) << 9u16 != num.Wrapping(2u8) ||
          num.Wrapping(1u8) << 10u32 != num.Wrapping(4u8) ||
          num.Wrapping(1u8) << 11u64 != num.Wrapping(8u8) ||
          num.Wrapping(1u8) << 12u128 != num.Wrapping(16u8) ||
          num.Wrapping(1u8) << 13usize != num.Wrapping(32u8) ||
          num.Wrapping(1u8) << -1i8 != num.Wrapping(128u8) ||
          num.Wrapping(1u8) << -2i16 != num.Wrapping(64u8) ||
          num.Wrapping(1u8) << -3i32 != num.Wrapping(32u8) ||
          num.Wrapping(1u8) << -4i64 != num.Wrapping(16u8) ||
          num.Wrapping(1u8) << -5i128 != num.Wrapping(8u8) ||
          num.Wrapping(1u8) << -6isize != num.Wrapping(4u8) ||
          num.Wrapping(1u8) << 4294967297u64 != num.Wrapping(2u8) ||
          num.Wrapping(1u8) << 18446744073709551618u128 != num.Wrapping(4u8) {
          return 59
    }
    let wrapped_from = num.Wrapping<i32>.(core.convert.From<i32>).`from`(23)
    let wrapped_clone = wrapped_from.clone()
    let wrapped_default = num.Wrapping<i32>.(core.default.Default).default()
    if wrapped_from.value != 23 || wrapped_clone.value != 23 || wrapped_default.value != 0 ||
          !(num.Wrapping(3i32) < num.Wrapping(4i32)) ||
          !debug_matches(wrapped_from, "Wrapping(23)") ||
          !display_matches(wrapped_from, "23") ||
          core.hash.hash_one(read wrapped_from) != core.hash.hash_one(read 23i32) {
          return 73
    }
    if !check_wrapping(
          num.Wrapping(13u8), num.Wrapping(3u8),
          num.Wrapping(16u8), num.Wrapping(10u8), num.Wrapping(39u8),
          num.Wrapping(4u8), num.Wrapping(1u8),
          num.Wrapping(1u8), num.Wrapping(15u8), num.Wrapping(14u8),
          num.Wrapping(243u8), num.Wrapping(242u8),
          num.Wrapping(26u8), num.Wrapping(6u8)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(255u8), num.Wrapping(0u8), num.Wrapping(1u8), num.Wrapping(2u8),
          num.Wrapping(0u8), num.Wrapping(255u8),
          num.Wrapping(254u8)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13u8), num.Wrapping(3u8),
          num.Wrapping(16u8), num.Wrapping(10u8), num.Wrapping(39u8),
          num.Wrapping(4u8), num.Wrapping(1u8),
          num.Wrapping(1u8), num.Wrapping(15u8), num.Wrapping(14u8),
          num.Wrapping(26u8), num.Wrapping(6u8)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13u16), num.Wrapping(3u16),
          num.Wrapping(16u16), num.Wrapping(10u16), num.Wrapping(39u16),
          num.Wrapping(4u16), num.Wrapping(1u16),
          num.Wrapping(1u16), num.Wrapping(15u16), num.Wrapping(14u16),
          num.Wrapping(65523u16), num.Wrapping(65522u16),
          num.Wrapping(26u16), num.Wrapping(6u16)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(65535u16), num.Wrapping(0u16), num.Wrapping(1u16), num.Wrapping(2u16),
          num.Wrapping(0u16), num.Wrapping(65535u16),
          num.Wrapping(65534u16)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13u16), num.Wrapping(3u16),
          num.Wrapping(16u16), num.Wrapping(10u16), num.Wrapping(39u16),
          num.Wrapping(4u16), num.Wrapping(1u16),
          num.Wrapping(1u16), num.Wrapping(15u16), num.Wrapping(14u16),
          num.Wrapping(26u16), num.Wrapping(6u16)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13u32), num.Wrapping(3u32),
          num.Wrapping(16u32), num.Wrapping(10u32), num.Wrapping(39u32),
          num.Wrapping(4u32), num.Wrapping(1u32),
          num.Wrapping(1u32), num.Wrapping(15u32), num.Wrapping(14u32),
          num.Wrapping(4294967283u32), num.Wrapping(4294967282u32),
          num.Wrapping(26u32), num.Wrapping(6u32)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(4294967295u32), num.Wrapping(0u32), num.Wrapping(1u32), num.Wrapping(2u32),
          num.Wrapping(0u32), num.Wrapping(4294967295u32),
          num.Wrapping(4294967294u32)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13u32), num.Wrapping(3u32),
          num.Wrapping(16u32), num.Wrapping(10u32), num.Wrapping(39u32),
          num.Wrapping(4u32), num.Wrapping(1u32),
          num.Wrapping(1u32), num.Wrapping(15u32), num.Wrapping(14u32),
          num.Wrapping(26u32), num.Wrapping(6u32)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13u64), num.Wrapping(3u64),
          num.Wrapping(16u64), num.Wrapping(10u64), num.Wrapping(39u64),
          num.Wrapping(4u64), num.Wrapping(1u64),
          num.Wrapping(1u64), num.Wrapping(15u64), num.Wrapping(14u64),
          num.Wrapping(18446744073709551603u64), num.Wrapping(18446744073709551602u64),
          num.Wrapping(26u64), num.Wrapping(6u64)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(18446744073709551615u64), num.Wrapping(0u64), num.Wrapping(1u64), num.Wrapping(2u64),
          num.Wrapping(0u64), num.Wrapping(18446744073709551615u64),
          num.Wrapping(18446744073709551614u64)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13u64), num.Wrapping(3u64),
          num.Wrapping(16u64), num.Wrapping(10u64), num.Wrapping(39u64),
          num.Wrapping(4u64), num.Wrapping(1u64),
          num.Wrapping(1u64), num.Wrapping(15u64), num.Wrapping(14u64),
          num.Wrapping(26u64), num.Wrapping(6u64)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13u128), num.Wrapping(3u128),
          num.Wrapping(16u128), num.Wrapping(10u128), num.Wrapping(39u128),
          num.Wrapping(4u128), num.Wrapping(1u128),
          num.Wrapping(1u128), num.Wrapping(15u128), num.Wrapping(14u128),
          num.Wrapping(340282366920938463463374607431768211443u128), num.Wrapping(340282366920938463463374607431768211442u128),
          num.Wrapping(26u128), num.Wrapping(6u128)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(340282366920938463463374607431768211455u128), num.Wrapping(0u128), num.Wrapping(1u128), num.Wrapping(2u128),
          num.Wrapping(0u128), num.Wrapping(340282366920938463463374607431768211455u128),
          num.Wrapping(340282366920938463463374607431768211454u128)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13u128), num.Wrapping(3u128),
          num.Wrapping(16u128), num.Wrapping(10u128), num.Wrapping(39u128),
          num.Wrapping(4u128), num.Wrapping(1u128),
          num.Wrapping(1u128), num.Wrapping(15u128), num.Wrapping(14u128),
          num.Wrapping(26u128), num.Wrapping(6u128)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13usize), num.Wrapping(3usize),
          num.Wrapping(16usize), num.Wrapping(10usize), num.Wrapping(39usize),
          num.Wrapping(4usize), num.Wrapping(1usize),
          num.Wrapping(1usize), num.Wrapping(15usize), num.Wrapping(14usize),
          num.Wrapping(18446744073709551603usize), num.Wrapping(18446744073709551602usize),
          num.Wrapping(26usize), num.Wrapping(6usize)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(18446744073709551615usize), num.Wrapping(0usize), num.Wrapping(1usize), num.Wrapping(2usize),
          num.Wrapping(0usize), num.Wrapping(18446744073709551615usize),
          num.Wrapping(18446744073709551614usize)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13usize), num.Wrapping(3usize),
          num.Wrapping(16usize), num.Wrapping(10usize), num.Wrapping(39usize),
          num.Wrapping(4usize), num.Wrapping(1usize),
          num.Wrapping(1usize), num.Wrapping(15usize), num.Wrapping(14usize),
          num.Wrapping(26usize), num.Wrapping(6usize)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13i8), num.Wrapping(3i8),
          num.Wrapping(16i8), num.Wrapping(10i8), num.Wrapping(39i8),
          num.Wrapping(4i8), num.Wrapping(1i8),
          num.Wrapping(1i8), num.Wrapping(15i8), num.Wrapping(14i8),
          num.Wrapping(-13i8), num.Wrapping(-14i8),
          num.Wrapping(26i8), num.Wrapping(6i8)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(127i8), num.Wrapping(0i8), num.Wrapping(1i8), num.Wrapping(2i8),
          num.Wrapping(-128i8), num.Wrapping(-1i8),
          num.Wrapping(-2i8)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13i8), num.Wrapping(3i8),
          num.Wrapping(16i8), num.Wrapping(10i8), num.Wrapping(39i8),
          num.Wrapping(4i8), num.Wrapping(1i8),
          num.Wrapping(1i8), num.Wrapping(15i8), num.Wrapping(14i8),
          num.Wrapping(26i8), num.Wrapping(6i8)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13i16), num.Wrapping(3i16),
          num.Wrapping(16i16), num.Wrapping(10i16), num.Wrapping(39i16),
          num.Wrapping(4i16), num.Wrapping(1i16),
          num.Wrapping(1i16), num.Wrapping(15i16), num.Wrapping(14i16),
          num.Wrapping(-13i16), num.Wrapping(-14i16),
          num.Wrapping(26i16), num.Wrapping(6i16)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(32767i16), num.Wrapping(0i16), num.Wrapping(1i16), num.Wrapping(2i16),
          num.Wrapping(-32768i16), num.Wrapping(-1i16),
          num.Wrapping(-2i16)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13i16), num.Wrapping(3i16),
          num.Wrapping(16i16), num.Wrapping(10i16), num.Wrapping(39i16),
          num.Wrapping(4i16), num.Wrapping(1i16),
          num.Wrapping(1i16), num.Wrapping(15i16), num.Wrapping(14i16),
          num.Wrapping(26i16), num.Wrapping(6i16)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13i32), num.Wrapping(3i32),
          num.Wrapping(16i32), num.Wrapping(10i32), num.Wrapping(39i32),
          num.Wrapping(4i32), num.Wrapping(1i32),
          num.Wrapping(1i32), num.Wrapping(15i32), num.Wrapping(14i32),
          num.Wrapping(-13i32), num.Wrapping(-14i32),
          num.Wrapping(26i32), num.Wrapping(6i32)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(2147483647i32), num.Wrapping(0i32), num.Wrapping(1i32), num.Wrapping(2i32),
          num.Wrapping(-2147483648i32), num.Wrapping(-1i32),
          num.Wrapping(-2i32)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13i32), num.Wrapping(3i32),
          num.Wrapping(16i32), num.Wrapping(10i32), num.Wrapping(39i32),
          num.Wrapping(4i32), num.Wrapping(1i32),
          num.Wrapping(1i32), num.Wrapping(15i32), num.Wrapping(14i32),
          num.Wrapping(26i32), num.Wrapping(6i32)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13i64), num.Wrapping(3i64),
          num.Wrapping(16i64), num.Wrapping(10i64), num.Wrapping(39i64),
          num.Wrapping(4i64), num.Wrapping(1i64),
          num.Wrapping(1i64), num.Wrapping(15i64), num.Wrapping(14i64),
          num.Wrapping(-13i64), num.Wrapping(-14i64),
          num.Wrapping(26i64), num.Wrapping(6i64)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(9223372036854775807i64), num.Wrapping(0i64), num.Wrapping(1i64), num.Wrapping(2i64),
          num.Wrapping(-9223372036854775808i64), num.Wrapping(-1i64),
          num.Wrapping(-2i64)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13i64), num.Wrapping(3i64),
          num.Wrapping(16i64), num.Wrapping(10i64), num.Wrapping(39i64),
          num.Wrapping(4i64), num.Wrapping(1i64),
          num.Wrapping(1i64), num.Wrapping(15i64), num.Wrapping(14i64),
          num.Wrapping(26i64), num.Wrapping(6i64)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13i128), num.Wrapping(3i128),
          num.Wrapping(16i128), num.Wrapping(10i128), num.Wrapping(39i128),
          num.Wrapping(4i128), num.Wrapping(1i128),
          num.Wrapping(1i128), num.Wrapping(15i128), num.Wrapping(14i128),
          num.Wrapping(-13i128), num.Wrapping(-14i128),
          num.Wrapping(26i128), num.Wrapping(6i128)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(170141183460469231731687303715884105727i128), num.Wrapping(0i128), num.Wrapping(1i128), num.Wrapping(2i128),
          num.Wrapping(-170141183460469231731687303715884105728i128), num.Wrapping(-1i128),
          num.Wrapping(-2i128)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13i128), num.Wrapping(3i128),
          num.Wrapping(16i128), num.Wrapping(10i128), num.Wrapping(39i128),
          num.Wrapping(4i128), num.Wrapping(1i128),
          num.Wrapping(1i128), num.Wrapping(15i128), num.Wrapping(14i128),
          num.Wrapping(26i128), num.Wrapping(6i128)) { return 72 }
    if !check_wrapping(
          num.Wrapping(13isize), num.Wrapping(3isize),
          num.Wrapping(16isize), num.Wrapping(10isize), num.Wrapping(39isize),
          num.Wrapping(4isize), num.Wrapping(1isize),
          num.Wrapping(1isize), num.Wrapping(15isize), num.Wrapping(14isize),
          num.Wrapping(-13isize), num.Wrapping(-14isize),
          num.Wrapping(26isize), num.Wrapping(6isize)) { return 70 }
    if !check_wrapping_overflow(
          num.Wrapping(9223372036854775807isize), num.Wrapping(0isize), num.Wrapping(1isize), num.Wrapping(2isize),
          num.Wrapping(-9223372036854775808isize), num.Wrapping(-1isize),
          num.Wrapping(-2isize)) { return 71 }
    if !check_wrapping_assign(
          num.Wrapping(13isize), num.Wrapping(3isize),
          num.Wrapping(16isize), num.Wrapping(10isize), num.Wrapping(39isize),
          num.Wrapping(4isize), num.Wrapping(1isize),
          num.Wrapping(1isize), num.Wrapping(15isize), num.Wrapping(14isize),
          num.Wrapping(26isize), num.Wrapping(6isize)) { return 72 }

    if !check_wrapping_shift_edges(num.Wrapping(1u8), 8u32, 9u32, 4294967295u32, num.Wrapping(0u8), num.Wrapping(1u8), num.Wrapping(2u8), num.Wrapping(128u8)) { return 60 }
    if !check_wrapping_shift_edges(num.Wrapping(1u16), 16u32, 17u32, 4294967295u32, num.Wrapping(0u16), num.Wrapping(1u16), num.Wrapping(2u16), num.Wrapping(32768u16)) { return 60 }
    if !check_wrapping_shift_edges(num.Wrapping(1u32), 32u32, 33u32, 4294967295u32, num.Wrapping(0u32), num.Wrapping(1u32), num.Wrapping(2u32), num.Wrapping(2147483648u32)) { return 60 }
    if !check_wrapping_shift_edges(num.Wrapping(1u64), 64u32, 65u32, 4294967295u32, num.Wrapping(0u64), num.Wrapping(1u64), num.Wrapping(2u64), num.Wrapping(9223372036854775808u64)) { return 60 }
    if !check_wrapping_shift_edges(num.Wrapping(1u128), 128u32, 129u32, 4294967295u32, num.Wrapping(0u128), num.Wrapping(1u128), num.Wrapping(2u128), num.Wrapping(170141183460469231731687303715884105728u128)) { return 60 }
    if !check_wrapping_shift_edges(num.Wrapping(1usize), 64u32, 65u32, 4294967295u32, num.Wrapping(0usize), num.Wrapping(1usize), num.Wrapping(2usize), num.Wrapping(9223372036854775808usize)) { return 60 }
    if !check_wrapping_shift_edges(num.Wrapping(1i8), 8u32, 9u32, 4294967295u32, num.Wrapping(0i8), num.Wrapping(1i8), num.Wrapping(2i8), num.Wrapping(-128i8)) { return 60 }
    if !check_wrapping_signed_div_edges(num.Wrapping(-128i8), num.Wrapping(-1i8), num.Wrapping(0i8)) { return 61 }
    if !check_wrapping_shift_edges(num.Wrapping(1i16), 16u32, 17u32, 4294967295u32, num.Wrapping(0i16), num.Wrapping(1i16), num.Wrapping(2i16), num.Wrapping(-32768i16)) { return 60 }
    if !check_wrapping_signed_div_edges(num.Wrapping(-32768i16), num.Wrapping(-1i16), num.Wrapping(0i16)) { return 61 }
    if !check_wrapping_shift_edges(num.Wrapping(1i32), 32u32, 33u32, 4294967295u32, num.Wrapping(0i32), num.Wrapping(1i32), num.Wrapping(2i32), num.Wrapping(-2147483648i32)) { return 60 }
    if !check_wrapping_signed_div_edges(num.Wrapping(-2147483648i32), num.Wrapping(-1i32), num.Wrapping(0i32)) { return 61 }
    if !check_wrapping_shift_edges(num.Wrapping(1i64), 64u32, 65u32, 4294967295u32, num.Wrapping(0i64), num.Wrapping(1i64), num.Wrapping(2i64), num.Wrapping(-9223372036854775808i64)) { return 60 }
    if !check_wrapping_signed_div_edges(num.Wrapping(-9223372036854775808i64), num.Wrapping(-1i64), num.Wrapping(0i64)) { return 61 }
    if !check_wrapping_shift_edges(num.Wrapping(1i128), 128u32, 129u32, 4294967295u32, num.Wrapping(0i128), num.Wrapping(1i128), num.Wrapping(2i128), num.Wrapping(-170141183460469231731687303715884105728i128)) { return 60 }
    if !check_wrapping_signed_div_edges(num.Wrapping(-170141183460469231731687303715884105728i128), num.Wrapping(-1i128), num.Wrapping(0i128)) { return 61 }
    if !check_wrapping_shift_edges(num.Wrapping(1isize), 64u32, 65u32, 4294967295u32, num.Wrapping(0isize), num.Wrapping(1isize), num.Wrapping(2isize), num.Wrapping(-9223372036854775808isize)) { return 60 }
    if !check_wrapping_signed_div_edges(num.Wrapping(-9223372036854775808isize), num.Wrapping(-1isize), num.Wrapping(0isize)) { return 61 }
      match capture num.parse<i32>("123") { success(v) => { if v != 123 { return 1 } }, failure(e) => { return 2 } }
      match capture num.parse<i32>("-2147483648") { success(v) => { if v != -2147483648 { return 3 } }, failure(e) => { return 4 } }
      match capture num.parse<i64>("-9223372036854775808") { success(v) => { if v != -9223372036854775807i64 - 1i64 { return 5 } }, failure(e) => { return 6 } }
      match capture num.parse<u64>("18446744073709551615") { success(v) => { if v != 18446744073709551615u64 { return 7 } }, failure(e) => { return 8 } }
      match capture num.parse_radix<u8>("ff", 16u32) { success(v) => { if v != 255u8 { return 9 } }, failure(e) => { return 10 } }
      match capture num.parse_radix<i32>("-1010", 2u32) { success(v) => { if v != -10 { return 11 } }, failure(e) => { return 12 } }
      match capture num.parse<i32>("+7") { success(v) => { if v != 7 { return 13 } }, failure(e) => { return 14 } }
      match kind<i32>("") { present(k) => { if k != IntErrorKind.Empty { return 15 } }, none => { return 16 } }
      match kind<i32>("12a") { present(k) => { if k != IntErrorKind.InvalidDigit { return 17 } }, none => { return 18 } }
      match kind<i32>("-") { present(k) => { if k != IntErrorKind.InvalidDigit { return 19 } }, none => { return 20 } }
      match kind<u8>("256") { present(k) => { if k != IntErrorKind.PosOverflow { return 21 } }, none => { return 22 } }
      match kind<i8>("-129") { present(k) => { if k != IntErrorKind.NegOverflow { return 23 } }, none => { return 24 } }
      match kind<u8>("-1") { present(k) => { if k != IntErrorKind.InvalidDigit { return 25 } }, none => { return 26 } }
      match kind<u64>("18446744073709551616") { present(k) => { if k != IntErrorKind.PosOverflow { return 27 } }, none => { return 28 } }
      match kind<i32>("99999999999999999999999x") { present(k) => { if k != IntErrorKind.InvalidDigit { return 29 } }, none => { return 30 } }
      match kind<i32>("1") { present(k) => { return 31 }, none => {} }
      match capture num.parse<i128>("-170141183460469231731687303715884105728") {
            success(v) => { if v != -170141183460469231731687303715884105728i128 { return 32 } },
            failure(e) => { return 33 }
      }
      match capture num.parse<i128>("170141183460469231731687303715884105727") {
            success(v) => { if v != 170141183460469231731687303715884105727i128 { return 34 } },
            failure(e) => { return 35 }
      }
      match capture num.parse_radix<u128>("ffffffffffffffffffffffffffffffff", 16u32) {
            success(v) => { if v != 340282366920938463463374607431768211455u128 { return 36 } },
            failure(e) => { return 37 }
      }
      match kind<u128>("340282366920938463463374607431768211456") {
            present(k) => { if k != IntErrorKind.PosOverflow { return 38 } },
            none => { return 39 }
      }
      match kind<i128>("-170141183460469231731687303715884105729") {
            present(k) => { if k != IntErrorKind.NegOverflow { return 40 } },
            none => { return 41 }
      }
      match kind<u128>("340282366920938463463374607431768211456x") {
            present(k) => { if k != IntErrorKind.InvalidDigit { return 42 } },
            none => { return 43 }
      }
      match capture num.parse<i8>("-128") { success(v) => { if v != -128i8 { return 44 } }, failure(e) => { return 45 } }
      match capture num.parse<i16>("32767") { success(v) => { if v != 32767i16 { return 46 } }, failure(e) => { return 47 } }
      match capture num.parse<u16>("65535") { success(v) => { if v != 65535u16 { return 48 } }, failure(e) => { return 49 } }
      match capture num.parse<u32>("4294967295") { success(v) => { if v != 4294967295u32 { return 50 } }, failure(e) => { return 51 } }
      match capture num.parse<isize>("-9223372036854775808") { success(v) => { if v != -9223372036854775808isize { return 52 } }, failure(e) => { return 53 } }
      match capture num.parse<usize>("18446744073709551615") { success(v) => { if v != 18446744073709551615usize { return 54 } }, failure(e) => { return 55 } }
      let gap = check_integer_operation_gaps()
      if gap != 0 { return 100 + gap }
      0
}
