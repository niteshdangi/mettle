// Display and Debug for f32/f64 without any C library: the shortest decimal
// digits that read back as the same value (Steele-White/Dragon4 in the
// Burger-Dybvig free-format form) computed with exact fixed-size big integers.
// The output is plain positional notation, never an exponent: `0.1`, `1`,
// `1500000`, `0.000001`. Display prints an integral value without a fractional
// part (`1`); Debug keeps `1.0`. NaN prints `NaN`, infinities `inf`/`-inf`, and
// negative zero `-0`. A specified precision rounds to that many fractional
// digits, ties to even. Width, fill, alignment, `plus` and `zero` follow the
// integer rules.
import super.fmt.{Align, Formatter, Write, Display, Debug, Error, LowerExp, UpperExp}
import super.cmp.{Eq, Ordering, PartialEq}
import super.clone.Clone
import super.convert.From
import super.error.{Error as CoreError}
import super.ops.{Add, AddAssign, Div, DivAssign, Mul, MulAssign}
import super.ops.{Neg, Rem, RemAssign, Sub, SubAssign}
import super.slice
import super.text.{FromStr, Text, from_utf8_unchecked}

pub copy enum FpCategory { Nan, Infinite, Zero, Subnormal, Normal }

extend FpCategory implements PartialEq {
    fn eq(read other: FpCategory): bool { (self as u8) == (other as u8) }
}
extend FpCategory implements Eq {}
extend FpCategory implements Clone {
    fn clone(): FpCategory { self }
}
extend FpCategory implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            FpCategory.Nan => try f.write_str("Nan"),
            FpCategory.Infinite => try f.write_str("Infinite"),
            FpCategory.Zero => try f.write_str("Zero"),
            FpCategory.Subnormal => try f.write_str("Subnormal"),
            FpCategory.Normal => try f.write_str("Normal")
        }
    }
}

copy enum FloatErrorKind { Empty, Invalid }
extend FloatErrorKind implements PartialEq {
    fn eq(read other: FloatErrorKind): bool { (self as u8) == (other as u8) }
}
extend FloatErrorKind implements Eq {}
extend FloatErrorKind implements Clone {
    fn clone(): FloatErrorKind { self }
}
extend FloatErrorKind implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self {
            FloatErrorKind.Empty => try f.write_str("Empty"),
            FloatErrorKind.Invalid => try f.write_str("Invalid")
        }
    }
}

pub type ParseFloatError { kind: FloatErrorKind }
extend ParseFloatError implements PartialEq {
    fn eq(read other: ParseFloatError): bool { self.kind == other.kind }
}
extend ParseFloatError implements Eq {}
extend ParseFloatError implements Clone {
    fn clone(): ParseFloatError { ParseFloatError(self.kind.clone()) }
}
extend ParseFloatError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_struct("ParseFloatError")
        try debug.field("kind", read self.kind)
        try debug.finish()
    }
}
extend ParseFloatError implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        match self.kind {
            FloatErrorKind.Empty => try f.write_str("cannot parse float from empty string"),
            FloatErrorKind.Invalid => try f.write_str("invalid float literal")
        }
    }
}
extend ParseFloatError implements CoreError {}

fn empty_parse_float_error(): ParseFloatError {
    ParseFloatError(FloatErrorKind.Empty)
}

fn invalid_parse_float_error(): ParseFloatError {
    ParseFloatError(FloatErrorKind.Invalid)
}

// 256 little-endian limbs hold exact conversion intermediates through the
// f64 subnormal range; `len` counts significant limbs, so zero has none.
type Big { limbs: [u32; 256]; len: usize }

fn big_from(value: u64): Big {
    var big = Big([0u32; 256], 2usize)
    big.limbs[0usize] = (value & 0xffffffffu64) as u32
    big.limbs[1usize] = (value >> 32u64) as u32
    big.trim()
    big
}

fn big_copy(read source: Big): Big {
    var big = Big([0u32; 256], source.len)
    var i = 0usize
    while i < source.len {
        big.limbs[i] = source.limbs[i]
        i += 1usize
    }
    big
}

// -1, 0 or 1 as `left` is less than, equal to or greater than `right`.
fn big_compare(read left: Big, read right: Big): i32 {
    if left.len < right.len { return -1 }
    if left.len > right.len { return 1 }
    var i = left.len
    while i > 0usize {
        i -= 1usize
        if left.limbs[i] < right.limbs[i] { return -1 }
        if left.limbs[i] > right.limbs[i] { return 1 }
    }
    0
}

// Compares `value + extra` with `limit` without changing either operand.
fn big_sum_compare(read value: Big, read extra: Big, read limit: Big): i32 {
    var sum = big_copy(value)
    sum.add(extra)
    big_compare(read sum, limit)
}

extend Big {
    mut fn trim(): Unit {
        while self.len > 0usize && self.limbs[self.len - 1usize] == 0u32 {
            self.len -= 1usize
        }
    }

    mut fn mul_small(factor: u32): Unit {
        var carry = 0u64
        var i = 0usize
        while i < self.len {
            let product = (self.limbs[i] as u64) * (factor as u64) + carry
            self.limbs[i] = (product & 0xffffffffu64) as u32
            carry = product >> 32u64
            i += 1usize
        }
        if carry != 0u64 {
            self.limbs[self.len] = carry as u32
            self.len += 1usize
        }
    }

    mut fn mul_pow10(exponent: usize): Unit {
        var rest = exponent
        while rest >= 9usize {
            self.mul_small(1000000000u32)
            rest -= 9usize
        }
        while rest > 0usize {
            self.mul_small(10u32)
            rest -= 1usize
        }
    }

    mut fn shift_left(bits: usize): Unit {
        if self.len > 0usize {
            let words = bits / 32usize
            let rest = (bits % 32usize) as u32
            var shifted = [0u32; 256]
            var i = 0usize
            while i < self.len {
                shifted[i + words] = shifted[i + words] | (self.limbs[i] << rest)
                if rest > 0u32 {
                    shifted[i + words + 1usize] =
                        shifted[i + words + 1usize] | (self.limbs[i] >> (32u32 - rest))
                }
                i += 1usize
            }
            self.limbs = shifted
            self.len = self.len + words + 1usize
            self.trim()
        }
    }

    mut fn add(read other: Big): Unit {
        var count = if self.len > other.len { self.len } else { other.len }
        var carry = 0u64
        var i = 0usize
        while i < count {
            let sum = (self.limbs[i] as u64) + (other.limbs[i] as u64) + carry
            self.limbs[i] = (sum & 0xffffffffu64) as u32
            carry = sum >> 32u64
            i += 1usize
        }
        if carry != 0u64 {
            self.limbs[count] = carry as u32
            count += 1usize
        }
        self.len = count
    }

    mut fn add_small(value: u32): Unit {
        var carry = value as u64
        var i = 0usize
        while carry != 0u64 && i < self.len {
            let sum = (self.limbs[i] as u64) + carry
            self.limbs[i] = (sum & 0xffffffffu64) as u32
            carry = sum >> 32u64
            i += 1usize
        }
        if carry != 0u64 {
            self.limbs[self.len] = carry as u32
            self.len += 1usize
        }
    }

    mut fn div_small(divisor: u32): u32 {
        var remainder = 0u64
        var i = self.len
        while i > 0usize {
            i -= 1usize
            let current = (remainder << 32u64) | (self.limbs[i] as u64)
            self.limbs[i] = (current / (divisor as u64)) as u32
            remainder = current % (divisor as u64)
        }
        self.trim()
        remainder as u32
    }

    // Requires `self >= other`.
    mut fn sub(read other: Big): Unit {
        var borrow = 0i64
        var i = 0usize
        while i < self.len {
            var difference = (self.limbs[i] as i64) - (other.limbs[i] as i64) - borrow
            if difference < 0i64 {
                difference += 4294967296i64
                borrow = 1i64
            } else {
                borrow = 0i64
            }
            self.limbs[i] = difference as u32
            i += 1usize
        }
        self.trim()
    }
}

fn big_bit_length(read value: Big): i32 {
    if value.len == 0usize { return 0i32 }
    let top_index = value.len - 1usize
    var top = value.limbs[top_index]
    var bits = ((top_index + 1usize) * 32usize) as i32
    while top > 0u32 && (top & 0x80000000u32) == 0u32 {
        top = top << 1u32
        bits -= 1i32
    }
    bits
}

fn big_ratio_exponent(read numerator: Big, read denominator: Big): i32 {
    var exponent = big_bit_length(numerator) - big_bit_length(denominator)
    if exponent >= 0i32 {
        var scaled = big_copy(read denominator)
        scaled.shift_left(exponent as usize)
        if big_compare(numerator, read scaled) < 0i32 { exponent -= 1i32 }
    } else {
        var scaled = big_copy(read numerator)
        scaled.shift_left((0i32 - exponent) as usize)
        if big_compare(read scaled, denominator) < 0i32 { exponent -= 1i32 }
    }
    exponent
}

// Leaves the remainder in `numerator`; the quotient is bounded by the
// destination significand width at each call site.
fn big_div_u64(mut numerator: Big, read denominator: Big): u64 {
    var shift = big_bit_length(read numerator) - big_bit_length(denominator)
    var quotient = 0u64
    while shift >= 0i32 {
        var shifted = big_copy(read denominator)
        shifted.shift_left(shift as usize)
        if big_compare(read numerator, read shifted) >= 0i32 {
            numerator.sub(read shifted)
            quotient = quotient | (1u64 << (shift as u64))
        }
        if shift == 0i32 { break }
        shift -= 1i32
    }
    quotient
}

fn big_round_ratio(
    read numerator: Big,
    read denominator: Big,
    binary_shift: i32,
    sticky: bool
): u64 {
    var scaled_numerator = big_copy(read numerator)
    var scaled_denominator = big_copy(read denominator)
    if binary_shift >= 0i32 {
        scaled_numerator.shift_left(binary_shift as usize)
    } else {
        scaled_denominator.shift_left((0i32 - binary_shift) as usize)
    }
    let quotient = big_div_u64(mut scaled_numerator, read scaled_denominator)
    var twice_remainder = big_copy(read scaled_numerator)
    twice_remainder.mul_small(2u32)
    let half_order = big_compare(read twice_remainder, read scaled_denominator)
    if half_order > 0i32 ||
       (half_order == 0i32 && (sticky || (quotient & 1u64) != 0u64)) {
        quotient + 1u64
    } else {
        quotient
    }
}

// floor(value * log10(2)), never above the exact floor for the exponents used.
fn log10_floor(exponent: i32): i32 {
    let scaled = (exponent as i64) * 78913i64
    if scaled >= 0i64 { return (scaled / 262144i64) as i32 }
    (0i64 - ((0i64 - scaled + 262143i64) / 262144i64)) as i32
}

fn ascii_lower(byte: u8): u8 {
    if byte >= 0x41u8 && byte <= 0x5au8 { byte + 0x20u8 } else { byte }
}

fn keyword_at(read bytes: [u8], start: usize, first: u8, second: u8, third: u8): bool {
    bytes.len() - start == 3usize &&
    ascii_lower(bytes[start]) == first &&
    ascii_lower(bytes[start + 1usize]) == second &&
    ascii_lower(bytes[start + 2usize]) == third
}

fn float_inf_at(read bytes: [u8], start: usize): bool {
    let remaining = bytes.len() - start
    if remaining == 3usize {
        return ascii_lower(bytes[start]) == 0x69u8 &&
            ascii_lower(bytes[start + 1usize]) == 0x6eu8 &&
            ascii_lower(bytes[start + 2usize]) == 0x66u8
    }
    remaining == 8usize &&
        ascii_lower(bytes[start]) == 0x69u8 &&
        ascii_lower(bytes[start + 1usize]) == 0x6eu8 &&
        ascii_lower(bytes[start + 2usize]) == 0x66u8 &&
        ascii_lower(bytes[start + 3usize]) == 0x69u8 &&
        ascii_lower(bytes[start + 4usize]) == 0x6eu8 &&
        ascii_lower(bytes[start + 5usize]) == 0x69u8 &&
        ascii_lower(bytes[start + 6usize]) == 0x74u8 &&
        ascii_lower(bytes[start + 7usize]) == 0x79u8
}

fn parse_ieee(
    read input: Text,
    fraction_bits: u32,
    exponent_bits: u32,
    exponent_bias: i32
): u64 throws ParseFloatError {
    let bytes = input.as_bytes()
    if bytes.len() == 0usize { throw empty_parse_float_error() }

    var index = 0usize
    var negative = false
    if bytes[index] == 0x2bu8 {
        index += 1usize
    } else if bytes[index] == 0x2du8 {
        negative = true
        index += 1usize
    }
    if index == bytes.len() { throw invalid_parse_float_error() }

    let sign_bit = if negative {
        1u64 << (fraction_bits + exponent_bits)
    } else {
        0u64
    }
    let exponent_mask = (1u64 << exponent_bits) - 1u64
    if keyword_at(read bytes, index, 0x6eu8, 0x61u8, 0x6eu8) {
        return sign_bit | (exponent_mask << fraction_bits) |
            (1u64 << (fraction_bits - 1u32))
    }
    if float_inf_at(read bytes, index) {
        return sign_bit | (exponent_mask << fraction_bits)
    }

    var mantissa = Big([0u32; 256], 0usize)
    var significant_digits = 0usize
    var dropped_digits = 0i64
    var fractional_digits = 0i64
    var sticky = false
    var significant = false
    var saw_digit = false
    var saw_point = false
    // Rounding boundaries terminate within 1075 decimal places; retaining
    // 1120 significant digits plus a sticky suffix covers every binary64 tie.
    while index < bytes.len() {
        let byte = bytes[index]
        if byte >= 0x30u8 && byte <= 0x39u8 {
            saw_digit = true
            let digit = (byte - 0x30u8) as u32
            if saw_point { fractional_digits += 1i64 }
            if digit != 0u32 || significant {
                significant = true
                if significant_digits < 1120usize {
                    mantissa.mul_small(10u32)
                    mantissa.add_small(digit)
                    significant_digits += 1usize
                } else {
                    dropped_digits += 1i64
                    if digit != 0u32 { sticky = true }
                }
            }
            index += 1usize
        } else if byte == 0x2eu8 && !saw_point {
            saw_point = true
            index += 1usize
        } else {
            break
        }
    }
    if !saw_digit { throw invalid_parse_float_error() }

    var explicit_exponent = 0i128
    // Saturation must exceed every cancellation by the input's decimal digits.
    let exponent_limit = bytes.len() as i128 + 2048i128
    if index < bytes.len() && (bytes[index] == 0x65u8 || bytes[index] == 0x45u8) {
        index += 1usize
        var exponent_negative = false
        if index < bytes.len() && bytes[index] == 0x2bu8 {
            index += 1usize
        } else if index < bytes.len() && bytes[index] == 0x2du8 {
            exponent_negative = true
            index += 1usize
        }
        let exponent_start = index
        while index < bytes.len() && bytes[index] >= 0x30u8 && bytes[index] <= 0x39u8 {
            let digit = (bytes[index] - 0x30u8) as i128
            if explicit_exponent < exponent_limit {
                explicit_exponent = explicit_exponent * 10i128 + digit
                if explicit_exponent > exponent_limit {
                    explicit_exponent = exponent_limit
                }
            }
            index += 1usize
        }
        if index == exponent_start { throw invalid_parse_float_error() }
        if exponent_negative { explicit_exponent = 0i128 - explicit_exponent }
    }
    if index != bytes.len() { throw invalid_parse_float_error() }
    if !significant { return sign_bit }

    let decimal_exponent_wide = explicit_exponent - fractional_digits as i128 + dropped_digits as i128
    let decimal_order = decimal_exponent_wide + significant_digits as i128 - 1i128
    let min_normal_exponent = 1i32 - exponent_bias
    let min_subnormal_exponent = min_normal_exponent - fraction_bits as i32
    let min_decimal_order = log10_floor(min_subnormal_exponent)
    if decimal_order < (min_decimal_order - 1i32) as i128 { return sign_bit }
    let max_decimal_order = log10_floor(exponent_bias + 1i32) + 2i32
    if decimal_order > max_decimal_order as i128 {
        return sign_bit | (exponent_mask << fraction_bits)
    }

    let decimal_exponent = decimal_exponent_wide as i64
    var numerator = mantissa
    var denominator = big_from(1u64)
    if decimal_exponent >= 0i64 {
        var count = 0i64
        while count < decimal_exponent {
            numerator.mul_small(10u32)
            count += 1i64
        }
    } else {
        var count = 0i64
        while count < (0i64 - decimal_exponent) {
            denominator.mul_small(10u32)
            count += 1i64
        }
    }

    let ratio_exponent = big_ratio_exponent(read numerator, read denominator)
    if ratio_exponent > exponent_bias {
        return sign_bit | (exponent_mask << fraction_bits)
    }
    if ratio_exponent < min_normal_exponent {
        let binary_shift = 0i32 - min_subnormal_exponent
        let rounded = big_round_ratio(
            read numerator, read denominator, binary_shift, sticky)
        if rounded == 0u64 { return sign_bit }
        if rounded >= (1u64 << fraction_bits) {
            return sign_bit | (1u64 << fraction_bits)
        }
        return sign_bit | rounded
    }

    var exponent = ratio_exponent
    var significand = big_round_ratio(
        read numerator, read denominator,
        (fraction_bits as i32) - exponent, sticky)
    if significand == (1u64 << (fraction_bits + 1u32)) {
        significand = significand >> 1u32
        exponent += 1i32
    }
    if exponent > exponent_bias {
        return sign_bit | (exponent_mask << fraction_bits)
    }
    let exponent_field = (exponent + exponent_bias) as u64
    sign_bit | (exponent_field << fraction_bits) |
        (significand - (1u64 << fraction_bits))
}

extend f32 implements FromStr {
    type Error = ParseFloatError
    static fn from_str(read input: Text): f32 throws ParseFloatError {
        f32.from_bits(try parse_ieee(input, 23u32, 8u32, 127i32) as u32)
    }
}

extend f64 implements FromStr {
    type Error = ParseFloatError
    static fn from_str(read input: Text): f64 throws ParseFloatError {
        f64.from_bits(try parse_ieee(input, 52u32, 11u32, 1023i32))
    }
}

// Writes the shortest digits of `mantissa * 2^exponent` (> 0) into `digits` and
// returns their count and the decimal exponent `k`: value = 0.d1d2... * 10^k.
// `unequal` marks a lower neighbour that is closer than the upper one.
fn shortest_digits(mantissa: u64, exponent: i32, unequal: bool, mut digits: [u8]): (usize, i32) {
    var r = big_from(mantissa)
    var s = big_from(1u64)
    var plus = big_from(1u64)
    var minus = big_from(1u64)
    if exponent >= 0 {
        if unequal {
            r.shift_left((exponent + 2) as usize)
            s.shift_left(2usize)
            plus.shift_left((exponent + 1) as usize)
            minus.shift_left(exponent as usize)
        } else {
            r.shift_left((exponent + 1) as usize)
            s.shift_left(1usize)
            plus.shift_left(exponent as usize)
            minus.shift_left(exponent as usize)
        }
    } else if unequal {
        r.shift_left(2usize)
        s.shift_left((2 - exponent) as usize)
        plus.shift_left(1usize)
    } else {
        r.shift_left(1usize)
        s.shift_left((1 - exponent) as usize)
    }
    // Round-to-even readers accept a boundary value, so it ends digits early.
    let even = (mantissa & 1u64) == 0u64
    var width = 0i32
    var scan = mantissa
    while scan > 0u64 {
        scan = scan >> 1u64
        width += 1
    }
    var k = log10_floor(exponent + width - 1)
    if k >= 0 {
        s.mul_pow10(k as usize)
    } else {
        r.mul_pow10((0 - k) as usize)
        plus.mul_pow10((0 - k) as usize)
        minus.mul_pow10((0 - k) as usize)
    }
    while true {
        let c = big_sum_compare(read r, read plus, read s)
        let again = if even { c >= 0 } else { c > 0 }
        if again {
            s.mul_small(10u32)
            k += 1
        } else {
            break
        }
    }
    var count = 0usize
    while true {
        r.mul_small(10u32)
        plus.mul_small(10u32)
        minus.mul_small(10u32)
        var digit = 0u8
        while big_compare(read r, read s) >= 0 {
            r.sub(read s)
            digit += 1u8
        }
        let low_compare = big_compare(read r, read minus)
        let low = if even { low_compare <= 0 } else { low_compare < 0 }
        let high_compare = big_sum_compare(read r, read plus, read s)
        let high = if even { high_compare >= 0 } else { high_compare > 0 }
        if !low && !high {
            digits[count] = 0x30u8 + digit
            count += 1usize
        } else {
            var round_up = high
            if low && high {
                var twice = big_copy(read r)
                twice.mul_small(2u32)
                round_up = big_compare(read twice, read s) >= 0
            }
            digits[count] = 0x30u8 + (if round_up { digit + 1u8 } else { digit })
            count += 1usize
            break
        }
    }
    (count, k)
}

// Formats a value given by its sign, stored fraction and biased exponent field.
fn fmt_float(mut f: Formatter, negative: bool, fraction: u64, biased: u64, fraction_bits: u64, exponent_bias: i32, special: u64, keep_point: bool): Unit throws Error {
    if biased == special {
        if fraction != 0u64 { return try f.pad_integral(true, "", "NaN") }
        return try f.pad_integral(!negative, "", "inf")
    }
    let hidden = 1u64 << fraction_bits
    let mantissa = if biased == 0u64 { fraction } else { fraction | hidden }
    // Both renderers below consume `mantissa * 2^exponent`.
    let exponent = if biased == 0u64 {
        1 - exponent_bias - (fraction_bits as i32)
    } else {
        (biased as i32) - exponent_bias - (fraction_bits as i32)
    }
    match f.precision() {
        present(precision) => {
            return try fmt_float_precision(mut f, negative, mantissa, exponent, precision)
        },
        none => {}
    }
    var digits = [0u8; 24]
    var count = 1usize
    var k = 1i32
    digits[0usize] = 0x30u8
    if mantissa != 0u64 {
        let produced = shortest_digits(mantissa, exponent, mantissa == hidden && biased > 1u64, mut digits)
        count = produced.0
        k = produced.1
    }
    // The longest result is a 309-digit integer or 0.(323 zeros)5.
    var out = [0u8; 400]
    var n = 0usize
    var i = 0usize
    if k <= 0 {
        out[0usize] = 0x30u8
        out[1usize] = 0x2eu8
        n = 2usize
        var zeros = 0 - k
        while zeros > 0 {
            out[n] = 0x30u8
            n += 1usize
            zeros -= 1
        }
        while i < count {
            out[n] = digits[i]
            n += 1usize
            i += 1usize
        }
    } else {
        let whole = k as usize
        while i < whole {
            out[n] = if i < count { digits[i] } else { 0x30u8 }
            n += 1usize
            i += 1usize
        }
        if count > whole {
            out[n] = 0x2eu8
            n += 1usize
            while i < count {
                out[n] = digits[i]
                n += 1usize
                i += 1usize
            }
        } else if keep_point {
            out[n] = 0x2eu8
            out[n + 1usize] = 0x30u8
            n += 2usize
        }
    }
    // ASCII digits and '.' only.
    let text = unsafe { from_utf8_unchecked(unsafe { slice.subslice_unchecked(read out, 0usize, n) }) }
    try f.pad_integral(!negative, "", text)
}

fn fmt_padding(mut f: Formatter, fill: char, count: usize): Unit throws Error {
    var i = 0usize
    while i < count {
        try f.write_char(fill)
        i += 1usize
    }
}

fn fmt_float_precision(
    mut f: Formatter,
    negative: bool,
    mantissa: u64,
    exponent: i32,
    precision: usize
): Unit throws Error {
    var whole = big_from(mantissa)
    var remainder_value = 0u64
    var binary_scale = 0usize
    if exponent >= 0 {
        whole.shift_left(exponent as usize)
    } else {
        binary_scale = (0 - exponent) as usize
        var whole_value = 0u64
        remainder_value = mantissa
        if binary_scale < 64usize {
            whole_value = mantissa >> (binary_scale as u64)
            remainder_value = mantissa - (whole_value << (binary_scale as u64))
        }
        whole = big_from(whole_value)
    }

    var reversed = [0u8; 310]
    var integer = [0u8; 310]
    var integer_len = 0usize
    while whole.len > 0usize {
        reversed[integer_len] = 0x30u8 + (whole.div_small(10u32) as u8)
        integer_len += 1usize
    }
    if integer_len == 0usize {
        integer[0usize] = 0x30u8
        integer_len = 1usize
    } else {
        var i = 0usize
        while i < integer_len {
            integer[i] = reversed[integer_len - i - 1usize]
            i += 1usize
        }
    }

    var fractional_digits = [0x30u8; 1074]
    var stored_fraction = precision
    if stored_fraction > binary_scale { stored_fraction = binary_scale }
    var generated = stored_fraction
    if precision < binary_scale { generated += 1usize }
    if remainder_value != 0u64 && generated > 0usize {
        var remainder = big_from(remainder_value)
        var denominator = big_from(1u64)
        denominator.shift_left(binary_scale)
        var i = 0usize
        while i < generated {
            remainder.mul_small(10u32)
            var digit = 0u8
            while big_compare(read remainder, read denominator) >= 0 {
                remainder.sub(read denominator)
                digit += 1u8
            }
            fractional_digits[i] = 0x30u8 + digit
            i += 1usize
        }
        if precision < binary_scale {
            let guard = fractional_digits[precision] - 0x30u8
            let sticky = remainder.len > 0usize
            var odd = false
            if precision > 0usize {
                odd = (fractional_digits[precision - 1usize] & 1u8) != 0u8
            } else {
                odd = (integer[integer_len - 1usize] & 1u8) != 0u8
            }
            let round_up = guard > 5u8 || (guard == 5u8 && (sticky || odd))
            if round_up {
                var carry = true
                var at = stored_fraction
                while at > 0usize {
                    at -= 1usize
                    if fractional_digits[at] < 0x39u8 {
                        fractional_digits[at] += 1u8
                        carry = false
                        break
                    }
                    fractional_digits[at] = 0x30u8
                }
                if carry {
                    at = integer_len
                    while at > 0usize {
                        at -= 1usize
                        if integer[at] < 0x39u8 {
                            integer[at] += 1u8
                            carry = false
                            break
                        }
                        integer[at] = 0x30u8
                    }
                    if carry {
                        at = integer_len
                        while at > 0usize {
                            integer[at] = integer[at - 1usize]
                            at -= 1usize
                        }
                        integer[0usize] = 0x31u8
                        integer_len += 1usize
                    }
                }
            }
        }
    }

    let options = f.options()
    let has_point = precision > 0usize || options.alternate
    let sign_len = if negative || options.plus { 1usize } else { 0usize }
    let point_len = if has_point { 1usize } else { 0usize }
    let fixed_prefix_len = sign_len + integer_len + point_len
    var padding = 0usize
    match options.width {
        present(width) => {
            if fixed_prefix_len < width {
                let remaining = width - fixed_prefix_len
                if precision < remaining { padding = remaining - precision }
            }
        },
        none => {}
    }

    if options.zero && padding > 0usize {
        if negative { try f.write_char('-') }
        else if options.plus { try f.write_char('+') }
        try fmt_padding(mut f, '0', padding)
    } else {
        var before = 0usize
        if padding > 0usize {
            match options.align {
                Align.Left => {},
                Align.Center => { before = padding / 2usize },
                Align.Right => { before = padding },
                Align.Unknown => { before = padding }
            }
        }
        try fmt_padding(mut f, options.fill, before)
        if negative { try f.write_char('-') }
        else if options.plus { try f.write_char('+') }
    }

    let integer_text = unsafe {
        from_utf8_unchecked(unsafe {
            slice.subslice_unchecked(read integer, 0usize, integer_len)
        })
    }
    try f.write_str(integer_text)
    if has_point { try f.write_char('.') }
    if stored_fraction > 0usize {
        let fraction_text = unsafe {
            from_utf8_unchecked(unsafe {
                slice.subslice_unchecked(read fractional_digits, 0usize, stored_fraction)
            })
        }
        try f.write_str(fraction_text)
    }
    var zeros = precision - stored_fraction
    while zeros > 0usize {
        try f.write_char('0')
        zeros -= 1usize
    }

    if !(options.zero && padding > 0usize) {
        var before = 0usize
        if padding > 0usize {
            match options.align {
                Align.Left => {},
                Align.Center => { before = padding / 2usize },
                Align.Right => { before = padding },
                Align.Unknown => { before = padding }
            }
        }
        try fmt_padding(mut f, options.fill, padding - before)
    }
}

fn fmt_float_exponent(
    mut f: Formatter,
    negative: bool,
    fraction: u64,
    biased: u64,
    fraction_bits: u64,
    exponent_bias: i32,
    special: u64,
    uppercase: bool
): Unit throws Error {
    if biased == special {
        if fraction != 0u64 { return try f.pad_integral(true, "", "NaN") }
        return try f.pad_integral(!negative, "", "inf")
    }

    let hidden = 1u64 << fraction_bits
    let mantissa = if biased == 0u64 { fraction } else { fraction | hidden }
    let binary_exponent = if biased == 0u64 {
        1 - exponent_bias - (fraction_bits as i32)
    } else {
        (biased as i32) - exponent_bias - (fraction_bits as i32)
    }
    // Binary floating-point values terminate within 1074 decimal places.
    var digits = [0u8; 1075]
    var stored_fraction = 0usize
    var output_fraction = 0usize
    var exponent10 = 0i32

    match f.precision() {
        present(precision) => {
            output_fraction = precision
            if mantissa == 0u64 {
                digits[0usize] = 0x30u8
            } else {
                var scratch = [0u8; 24]
                let decimal = shortest_digits(
                    mantissa,
                    binary_exponent,
                    mantissa == hidden && biased > 1u64,
                    mut scratch
                )
                exponent10 = decimal.1 - 1

                var numerator = big_from(mantissa)
                var denominator = big_from(1u64)
                if binary_exponent >= 0 {
                    numerator.shift_left(binary_exponent as usize)
                } else {
                    denominator.shift_left((0 - binary_exponent) as usize)
                }
                if exponent10 >= 0 {
                    denominator.mul_pow10(exponent10 as usize)
                } else {
                    numerator.mul_pow10((0 - exponent10) as usize)
                }

                var ten_denominator = big_copy(read denominator)
                ten_denominator.mul_small(10u32)
                if big_compare(read numerator, read ten_denominator) >= 0 {
                    denominator.mul_small(10u32)
                    exponent10 += 1i32
                }
                while big_compare(read numerator, read denominator) < 0 {
                    numerator.mul_small(10u32)
                    exponent10 -= 1i32
                }

                var leading = 0u8
                while big_compare(read numerator, read denominator) >= 0 {
                    numerator.sub(read denominator)
                    leading += 1u8
                }
                digits[0usize] = 0x30u8 + leading

                while stored_fraction < precision &&
                      stored_fraction < 1074usize &&
                      numerator.len > 0usize {
                    numerator.mul_small(10u32)
                    var digit = 0u8
                    while big_compare(read numerator, read denominator) >= 0 {
                        numerator.sub(read denominator)
                        digit += 1u8
                    }
                    digits[stored_fraction + 1usize] = 0x30u8 + digit
                    stored_fraction += 1usize
                }
                if stored_fraction < precision && numerator.len > 0usize {
                    super.panic.panic("float exponent precision invariant")
                }

                if numerator.len > 0usize {
                    var twice = big_copy(read numerator)
                    twice.mul_small(2u32)
                    let comparison = big_compare(read twice, read denominator)
                    let last = digits[stored_fraction]
                    let odd = ((last - 0x30u8) % 2u8) != 0u8
                    if comparison > 0 || (comparison == 0 && odd) {
                        var carry = true
                        var at = stored_fraction + 1usize
                        while at > 0usize {
                            at -= 1usize
                            if digits[at] < 0x39u8 {
                                digits[at] += 1u8
                                carry = false
                                break
                            }
                            digits[at] = 0x30u8
                        }
                        if carry {
                            digits[0usize] = 0x31u8
                            exponent10 += 1i32
                        }
                    }
                }
            }
        },
        none => {
            if mantissa == 0u64 {
                digits[0usize] = 0x30u8
            } else {
                let decimal = shortest_digits(
                    mantissa,
                    binary_exponent,
                    mantissa == hidden && biased > 1u64,
                    mut digits
                )
                stored_fraction = decimal.0 - 1usize
                output_fraction = stored_fraction
                exponent10 = decimal.1 - 1i32
            }
        }
    }

    var exponent_magnitude = if exponent10 < 0 {
        (0 - exponent10) as u32
    } else {
        exponent10 as u32
    }
    var exponent_width = 1usize
    var exponent_probe = exponent_magnitude
    while exponent_probe >= 10u32 {
        exponent_probe = exponent_probe / 10u32
        exponent_width += 1usize
    }
    let options = f.options()
    let has_point = output_fraction > 0usize || options.alternate
    let sign_length = if negative || options.plus { 1usize } else { 0usize }
    let point_length = if has_point { 1usize } else { 0usize }
    let exponent_length = 1usize + exponent_width +
        (if exponent10 < 0 { 1usize } else { 0usize })
    let fixed_length = sign_length + 1usize + point_length + exponent_length
    var padding = 0usize
    match options.width {
        present(width) => {
            if fixed_length < width {
                let remaining = width - fixed_length
                if output_fraction < remaining {
                    padding = remaining - output_fraction
                }
            }
        },
        none => {}
    }

    if options.zero && padding > 0usize {
        if negative { try f.write_char('-') }
        else if options.plus { try f.write_char('+') }
        var zeros = padding
        while zeros > 0usize {
            try f.write_char('0')
            zeros -= 1usize
        }
    } else {
        var before = 0usize
        if padding > 0usize {
            match options.align {
                Align.Left => {},
                Align.Center => { before = padding / 2usize },
                Align.Right => { before = padding },
                Align.Unknown => { before = padding }
            }
        }
        try fmt_padding(mut f, options.fill, before)
        if negative { try f.write_char('-') }
        else if options.plus { try f.write_char('+') }
    }

    try f.write_char(digits[0usize] as char)
    if has_point { try f.write_char('.') }
    var index = 0usize
    while index < stored_fraction {
        try f.write_char(digits[index + 1usize] as char)
        index += 1usize
    }
    var zeros = output_fraction - stored_fraction
    while zeros > 0usize {
        try f.write_char('0')
        zeros -= 1usize
    }

    try f.write_char(if uppercase { 'E' } else { 'e' })
    if exponent10 < 0 { try f.write_char('-') }
    var exponent_digits = [0u8; 10]
    var exponent_count = 0usize
    while exponent_magnitude > 0u32 {
        exponent_digits[exponent_count] =
            0x30u8 + (exponent_magnitude % 10u32) as u8
        exponent_magnitude = exponent_magnitude / 10u32
        exponent_count += 1usize
    }
    if exponent_count == 0usize {
        try f.write_char('0')
    } else {
        while exponent_count > 0usize {
            exponent_count -= 1usize
            try f.write_char(exponent_digits[exponent_count] as char)
        }
    }

    if !(options.zero && padding > 0usize) {
        var before = 0usize
        if padding > 0usize {
            match options.align {
                Align.Left => {},
                Align.Center => { before = padding / 2usize },
                Align.Right => { before = padding },
                Align.Unknown => { before = padding }
            }
        }
        try fmt_padding(mut f, options.fill, padding - before)
    }
}

fn fmt_f64(mut f: Formatter, value: f64, keep_point: bool): Unit throws Error {
    let bits = unsafe { core.mem.transmute<u64>(value) }
    try fmt_float(mut f, (bits >> 63u64) != 0u64, bits & 0xfffffffffffffu64, (bits >> 52u64) & 0x7ffu64, 52u64, 1023, 0x7ffu64, keep_point)
}

fn fmt_f64_exponent(mut f: Formatter, value: f64, uppercase: bool): Unit throws Error {
    let bits = unsafe { core.mem.transmute<u64>(value) }
    try fmt_float_exponent(mut f, (bits >> 63u64) != 0u64, bits & 0xfffffffffffffu64, (bits >> 52u64) & 0x7ffu64, 52u64, 1023, 0x7ffu64, uppercase)
}

fn fmt_f32(mut f: Formatter, value: f32, keep_point: bool): Unit throws Error {
    let bits = unsafe { core.mem.transmute<u32>(value) }
    try fmt_float(mut f, (bits >> 31u32) != 0u32, (bits & 0x7fffffu32) as u64, ((bits >> 23u32) & 0xffu32) as u64, 23u64, 127, 0xffu64, keep_point)
}

fn fmt_f32_exponent(mut f: Formatter, value: f32, uppercase: bool): Unit throws Error {
    let bits = unsafe { core.mem.transmute<u32>(value) }
    try fmt_float_exponent(mut f, (bits >> 31u32) != 0u32, (bits & 0x7fffffu32) as u64, ((bits >> 23u32) & 0xffu32) as u64, 23u64, 127, 0xffu64, uppercase)
}

extend f64 implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f64(mut f, self, false) }
}
extend f64 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f64(mut f, self, true) }
}
extend f64 implements LowerExp {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f64_exponent(mut f, self, false) }
}
extend f64 implements UpperExp {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f64_exponent(mut f, self, true) }
}
extend f32 implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f32(mut f, self, false) }
}
extend f32 implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f32(mut f, self, true) }
}
extend f32 implements LowerExp {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f32_exponent(mut f, self, false) }
}
extend f32 implements UpperExp {
    fn fmt(mut f: Formatter): Unit throws Error { try fmt_f32_exponent(mut f, self, true) }
}
// Map IEEE bit patterns to integer keys in total-order sequence.
extend f64 {
    pub fn total_cmp(other: f64): Ordering {
        let sign = 0x8000000000000000u64
        let left = self.to_bits()
        let right = other.to_bits()
        let left_key = if left & sign != 0u64 {
            0xffffffffffffffffu64 - left
        } else {
            left | sign
        }
        let right_key = if right & sign != 0u64 {
            0xffffffffffffffffu64 - right
        } else {
            right | sign
        }
        if left_key < right_key { Ordering.Less }
        else if left_key > right_key { Ordering.Greater }
        else { Ordering.Equal }
    }
}

extend f32 {
    pub fn total_cmp(other: f32): Ordering {
        let sign = 0x80000000u32
        let left = self.to_bits()
        let right = other.to_bits()
        let left_key = if left & sign != 0u32 {
            0xffffffffu32 - left
        } else {
            left | sign
        }
        let right_key = if right & sign != 0u32 {
            0xffffffffu32 - right
        } else {
            right | sign
        }
        if left_key < right_key { Ordering.Less }
        else if left_key > right_key { Ordering.Greater }
        else { Ordering.Equal }
    }
}

extend f64 {
    pub const fn classify(): FpCategory {
        if self.is_nan() { return FpCategory.Nan }
        if self.is_infinite() { return FpCategory.Infinite }
        if self == 0.0f64 { return FpCategory.Zero }
        if self.is_subnormal() { return FpCategory.Subnormal }
        FpCategory.Normal
    }
}

extend f32 {
    pub const fn classify(): FpCategory {
        if self.is_nan() { return FpCategory.Nan }
        if self.is_infinite() { return FpCategory.Infinite }
        if self == 0.0f32 { return FpCategory.Zero }
        if self.is_subnormal() { return FpCategory.Subnormal }
        FpCategory.Normal
    }
}

// These stable operations permit algebraic transformations but do not require
// them; strict primitive operators preserve a valid, deterministic result.
extend f32 {
    pub const fn algebraic_add(other: f32): f32 { self + other }
    pub const fn algebraic_sub(other: f32): f32 { self - other }
    pub const fn algebraic_mul(other: f32): f32 { self * other }
    pub const fn algebraic_div(other: f32): f32 { self / other }
    pub const fn algebraic_rem(other: f32): f32 { self % other }
}

extend f64 {
    pub const fn algebraic_add(other: f64): f64 { self + other }
    pub const fn algebraic_sub(other: f64): f64 { self - other }
    pub const fn algebraic_mul(other: f64): f64 { self * other }
    pub const fn algebraic_div(other: f64): f64 { self / other }
    pub const fn algebraic_rem(other: f64): f64 { self % other }
}

extend f32 implements From<bool> {
    static fn from(take value: bool): f32 {
        if value { 1.0f32 } else { 0.0f32 }
    }
}
extend f32 implements From<i8> {
    static fn from(take value: i8): f32 { value as f32 }
}
extend f32 implements From<i16> {
    static fn from(take value: i16): f32 { value as f32 }
}
extend f32 implements From<u8> {
    static fn from(take value: u8): f32 { value as f32 }
}
extend f32 implements From<u16> {
    static fn from(take value: u16): f32 { value as f32 }
}

extend f64 implements From<bool> {
    static fn from(take value: bool): f64 {
        if value { 1.0f64 } else { 0.0f64 }
    }
}
extend f64 implements From<i8> {
    static fn from(take value: i8): f64 { value as f64 }
}
extend f64 implements From<i16> {
    static fn from(take value: i16): f64 { value as f64 }
}
extend f64 implements From<i32> {
    static fn from(take value: i32): f64 { value as f64 }
}
extend f64 implements From<u8> {
    static fn from(take value: u8): f64 { value as f64 }
}
extend f64 implements From<u16> {
    static fn from(take value: u16): f64 { value as f64 }
}
extend f64 implements From<u32> {
    static fn from(take value: u32): f64 { value as f64 }
}
extend f64 implements From<f32> {
    static fn from(take value: f32): f64 { value as f64 }
}

macro float_binary_trait {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend $type implements $trait<$type> {
            type Output = $type
            fn $method(read rhs: $type): $type { self $operator rhs }
        }
        extend<region lhs_region> read $type from lhs_region implements $trait<$type> {
            type Output = $type
            fn $method(read rhs: $type): $type { *self $operator rhs }
        }
        extend<region rhs_region> $type implements $trait<read $type from rhs_region> {
            type Output = $type
            fn $method(read rhs: read $type from rhs_region): $type {
                self $operator *rhs
            }
        }
        extend<region lhs_region, region rhs_region> read $type from lhs_region implements $trait<read $type from rhs_region> {
            type Output = $type
            fn $method(read rhs: read $type from rhs_region): $type {
                *self $operator *rhs
            }
        }
    };
}

macro float_assignment_trait {
    ($type:ident, $trait:ident, $method:ident, $operator:tt) => {
        extend $type implements $trait<$type> {
            mut fn $method(read rhs: $type): Unit {
                self = self $operator rhs
            }
        }
        extend<region rhs_region> $type implements $trait<read $type from rhs_region> {
            mut fn $method(read rhs: read $type from rhs_region): Unit {
                self = self $operator *rhs
            }
        }
    };
}

macro float_neg_trait {
    ($type:ident) => {
        extend $type implements Neg {
            type Output = $type
            fn neg(): $type { -self }
        }
        extend<region receiver_region> read $type from receiver_region implements Neg {
            type Output = $type
            fn neg(): $type { -(*self) }
        }
    };
}

float_binary_trait!(f32, Add, add, +)
float_binary_trait!(f32, Sub, sub, -)
float_binary_trait!(f32, Mul, mul, *)
float_binary_trait!(f32, Div, div, /)
float_binary_trait!(f32, Rem, rem, %)
float_assignment_trait!(f32, AddAssign, add_assign, +)
float_assignment_trait!(f32, SubAssign, sub_assign, -)
float_assignment_trait!(f32, MulAssign, mul_assign, *)
float_assignment_trait!(f32, DivAssign, div_assign, /)
float_assignment_trait!(f32, RemAssign, rem_assign, %)
float_neg_trait!(f32)

float_binary_trait!(f64, Add, add, +)
float_binary_trait!(f64, Sub, sub, -)
float_binary_trait!(f64, Mul, mul, *)
float_binary_trait!(f64, Div, div, /)
float_binary_trait!(f64, Rem, rem, %)
float_assignment_trait!(f64, AddAssign, add_assign, +)
float_assignment_trait!(f64, SubAssign, sub_assign, -)
float_assignment_trait!(f64, MulAssign, mul_assign, *)
float_assignment_trait!(f64, DivAssign, div_assign, /)
float_assignment_trait!(f64, RemAssign, rem_assign, %)
float_neg_trait!(f64)
