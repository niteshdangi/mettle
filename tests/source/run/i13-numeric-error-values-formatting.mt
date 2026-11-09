import core.clone.Clone
import core.error.{Error as CoreError}
import core.float.FpCategory
import core.fmt
import core.fmt.Debug
import core.fmt.Display
import core.hash
import core.num
import core.num.IntErrorKind
import core.num.ParseIntError
import core.text.Text

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn display_is<T: Display>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    match capture fmt.write(mut writer, value) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn has_no_error_source<T: CoreError>(read value: T): bool {
    value.source().is_none()
}

fn main(): i32 {
    if !debug_is(FpCategory.Nan, "Nan") ||
       !debug_is(FpCategory.Infinite, "Infinite") ||
       !debug_is(FpCategory.Zero, "Zero") ||
       !debug_is(FpCategory.Subnormal, "Subnormal") ||
       !debug_is(FpCategory.Normal, "Normal") {
        return 1
    }
    if FpCategory.Normal.clone() != FpCategory.Normal { return 1 }

    let zero_error = IntErrorKind.Zero
    if !debug_is(IntErrorKind.InvalidDigit, "InvalidDigit") ||
       !debug_is(IntErrorKind.NegOverflow, "NegOverflow") ||
       !debug_is(IntErrorKind.Zero, "Zero") ||
       zero_error.clone() != zero_error ||
       hash.hash_one(read zero_error) != hash.hash_one(read zero_error.clone()) {
        return 2
    }

    match capture num.parse<i8>("") {
        success(value) => { return 3 },
        failure(empty) => {
            if empty != ParseIntError(IntErrorKind.Empty) ||
               !debug_is(read empty, "ParseIntError { kind: Empty }") ||
               !display_is(read empty, "cannot parse integer from empty string") ||
               !has_no_error_source(read empty) ||
               empty.clone() != empty {
                return 4
            }
            match capture num.parse<i8>("128") {
                success(value) => { return 5 },
                failure(overflow) => {
                    if overflow == empty ||
                       !debug_is(read overflow, "ParseIntError { kind: PosOverflow }") ||
                       !display_is(read overflow, "number too large to fit in target type") {
                        return 6
                    }
                }
            }
            match capture num.parse<i8>("-129") {
                success(value) => { return 7 },
                failure(underflow) => {
                    if !display_is(read underflow, "number too small to fit in target type") {
                        return 8
                    }
                }
            }
            if !display_is(
                   ParseIntError(IntErrorKind.Zero),
                   "number would be zero for non-zero type") {
                return 9
            }
            match capture num.parse_radix<i8>("1", 1u32) {
                success(value) => { return 10 },
                failure(radix) => {
                    if radix != ParseIntError(IntErrorKind.InvalidRadix) ||
                       !debug_is(read radix, "ParseIntError { kind: InvalidRadix }") ||
                       !display_is(read radix, "radix must be within 2..=36") {
                        return 11
                    }
                }
            }
        }
    }
    0
}
