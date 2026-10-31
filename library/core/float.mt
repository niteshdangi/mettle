// Display and Debug for f32/f64 without any C library: the shortest decimal
// digits that read back as the same value (Steele-White/Dragon4 in the
// Burger-Dybvig free-format form) computed with exact fixed-size big integers.
// The output is plain positional notation, never an exponent: `0.1`, `1`,
// `1500000`, `0.000001`. Display prints an integral value without a fractional
// part (`1`); Debug keeps `1.0`. NaN prints `NaN`, infinities `inf`/`-inf`, and
// negative zero `-0`. `Spec.precision` is not applied to floats yet. Width,
// fill, alignment, `plus` and `zero` follow the integer rules.
import super.fmt.{Formatter, Write, Display, Debug, Error}
import super.cmp.{Eq, Ordering, PartialEq}
import super.slice
import super.text.from_utf8_unchecked

pub copy enum FpCategory { Nan, Infinite, Zero, Subnormal, Normal }

extend FpCategory implements PartialEq {
    fn eq(other: read FpCategory): bool { (self as u8) == (other as u8) }
}
extend FpCategory implements Eq {}

// 40 little-endian 32-bit limbs hold every intermediate value for f64 (about
// 1100 bits at most); `len` counts the significant limbs, so zero has none.
type Big { limbs: [u32; 40]; len: usize }

fn big_from(value: u64): Big {
    var big = Big([0u32; 40], 2usize)
    big.limbs[0usize] = (value & 0xffffffffu64) as u32
    big.limbs[1usize] = (value >> 32u64) as u32
    big.trim()
    big
}

fn big_copy(source: read Big): Big {
    var big = Big([0u32; 40], source.len)
    var i = 0usize
    while i < source.len {
        big.limbs[i] = source.limbs[i]
        i += 1usize
    }
    big
}

// -1, 0 or 1 as `left` is less than, equal to or greater than `right`.
fn big_compare(left: read Big, right: read Big): i32 {
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
fn big_sum_compare(value: read Big, extra: read Big, limit: read Big): i32 {
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
            var shifted = [0u32; 40]
            var i = 0usize
            while i < self.len {
                shifted[i + words] = shifted[i + words] | (self.limbs[i] << rest)
                if rest > 0u32 {
                    shifted[i + words + 1usize] = self.limbs[i] >> (32u32 - rest)
                }
                i += 1usize
            }
            self.limbs = shifted
            self.len = self.len + words + 1usize
            self.trim()
        }
    }

    mut fn add(other: read Big): Unit {
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

    // Requires `self >= other`.
    mut fn sub(other: read Big): Unit {
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

// floor(value * log10(2)), never above the exact floor for the exponents used.
fn log10_floor(exponent: i32): i32 {
    let scaled = (exponent as i64) * 78913i64
    if scaled >= 0i64 { return (scaled / 262144i64) as i32 }
    (0i64 - ((0i64 - scaled + 262143i64) / 262144i64)) as i32
}

// Writes the shortest digits of `mantissa * 2^exponent` (> 0) into `digits` and
// returns their count and the decimal exponent `k`: value = 0.d1d2... * 10^k.
// `unequal` marks a lower neighbour that is closer than the upper one.
fn shortest_digits(mantissa: u64, exponent: i32, unequal: bool, digits: mut [u8]): (usize, i32) {
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
fn fmt_float<W: Write>(f: mut Formatter<W>, negative: bool, fraction: u64, biased: u64, fraction_bits: u64, bias: i32, special: u64, keep_point: bool): Unit throws Error {
    if biased == special {
        if fraction != 0u64 { return try f.pad("NaN") }
        return try f.pad_integral(!negative, "", "inf")
    }
    let hidden = 1u64 << fraction_bits
    let mantissa = if biased == 0u64 { fraction } else { fraction | hidden }
    let exponent = if biased == 0u64 { 1 - bias } else { (biased as i32) - bias }
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

fn fmt_f64<W: Write>(f: mut Formatter<W>, value: f64, keep_point: bool): Unit throws Error {
    let bits = unsafe { core.mem.transmute<u64>(value) }
    try fmt_float(mut f, (bits >> 63u64) != 0u64, bits & 0xfffffffffffffu64, (bits >> 52u64) & 0x7ffu64, 52u64, 1075, 0x7ffu64, keep_point)
}

fn fmt_f32<W: Write>(f: mut Formatter<W>, value: f32, keep_point: bool): Unit throws Error {
    let bits = unsafe { core.mem.transmute<u32>(value) }
    try fmt_float(mut f, (bits >> 31u32) != 0u32, (bits & 0x7fffffu32) as u64, ((bits >> 23u32) & 0xffu32) as u64, 23u64, 150, 0xffu64, keep_point)
}

extend f64 implements Display {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws Error { try fmt_f64(mut f, self, false) }
}
extend f64 implements Debug {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws Error { try fmt_f64(mut f, self, true) }
}
extend f32 implements Display {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws Error { try fmt_f32(mut f, self, false) }
}
extend f32 implements Debug {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws Error { try fmt_f32(mut f, self, true) }
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
    pub fn classify(): FpCategory {
        if self.is_nan() { return FpCategory.Nan }
        if self.is_infinite() { return FpCategory.Infinite }
        if self == 0.0f64 { return FpCategory.Zero }
        if self.is_subnormal() { return FpCategory.Subnormal }
        FpCategory.Normal
    }
}

extend f32 {
    pub fn classify(): FpCategory {
        if self.is_nan() { return FpCategory.Nan }
        if self.is_infinite() { return FpCategory.Infinite }
        if self == 0.0f32 { return FpCategory.Zero }
        if self.is_subnormal() { return FpCategory.Subnormal }
        FpCategory.Normal
    }
}
