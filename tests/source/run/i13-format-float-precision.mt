// expect-exit: 0
import core.float
import core.fmt
import core.fmt.{Debug, Display, Spec}
import core.text.Text

fn display_is<T: Display>(
    read value: T,
    options: Spec,
    read expected: Text
): bool {
    var storage = [0u8; 400]
    var writer = fmt.buffer_writer(mut storage)
    match capture fmt.write_with(mut writer, value, options) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read storage, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn debug_is<T: Debug>(
    read value: T,
    options: Spec,
    read expected: Text
): bool {
    var storage = [0u8; 400]
    var writer = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut writer, options)
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read storage, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn main(): i32 {
    var one_digit = fmt.spec()
    one_digit.precision = present(1usize)
    var two_digits = fmt.spec()
    two_digits.precision = present(2usize)
    if !display_is(1.25f64, one_digit, "1.2") ||
       !display_is(1.75f64, one_digit, "1.8") ||
       !display_is(2.5f64, two_digits, "2.50") {
        return 1
    }
    if !display_is(1.25f32, one_digit, "1.2") ||
       !debug_is(1.25f64, one_digit, "1.2") {
        return 2
    }

    if !display_is(1.2345f64, two_digits, "1.23") ||
       !display_is(9.999f64, two_digits, "10.00") ||
       !debug_is(1.25f32, one_digit, "1.2") {
        return 3
    }

    var no_fraction = fmt.spec()
    no_fraction.precision = present(0usize)
    if !display_is(2.5f64, no_fraction, "2") ||
       !display_is(3.5f64, no_fraction, "4") ||
       !display_is(9.5f64, no_fraction, "10") {
        return 4
    }
    two_digits.plus = true
    two_digits.zero = true
    two_digits.width = present(8usize)
    if !display_is(1.25f64, two_digits, "+0001.25") {
        return 5
    }
    two_digits.zero = false
    two_digits.fill = '*'
    two_digits.align = fmt.Align.Center
    if !display_is(1.25f64, two_digits, "*+1.25**") {
        return 6
    }

    two_digits = fmt.spec()
    two_digits.precision = present(2usize)
    if !display_is(-0.0f64, two_digits, "-0.00") ||
       !display_is(0.0f32, two_digits, "0.00") ||
       !display_is(2.0f64, two_digits, "2.00") {
        return 7
    }

    let tiny = 5e-324f64
    var tiny_options = fmt.spec()
    tiny_options.precision = present(324usize)
    var tiny_storage = [0u8; 400]
    var tiny_writer = fmt.buffer_writer(mut tiny_storage)
    match capture fmt.write_with(mut tiny_writer, tiny, tiny_options) {
        success(unit) => {},
        failure(error) => { return 8 }
    }
    if tiny_writer.len() != 326usize ||
       tiny_storage[0usize] != 0x30u8 ||
       tiny_storage[1usize] != 0x2eu8 ||
       tiny_storage[325usize] != 0x35u8 {
        return 9
    }
    var i = 2usize
    while i < 325usize {
        if tiny_storage[i] != 0x30u8 { return 10 }
        i += 1usize
    }

    tiny_options.precision = present(323usize)
    var rounded_storage = [0u8; 400]
    var rounded_writer = fmt.buffer_writer(mut rounded_storage)
    match capture fmt.write_with(mut rounded_writer, tiny, tiny_options) {
        success(unit) => {},
        failure(error) => { return 11 }
    }
    if rounded_writer.len() != 325usize ||
       rounded_storage[324usize] != 0x30u8 {
        return 12
    }

    var extended_precision = fmt.spec()
    extended_precision.precision = present(60usize)
    var extended_storage = [0u8; 80]
    var extended_writer = fmt.buffer_writer(mut extended_storage)
    match capture fmt.write_with(mut extended_writer, 0.5f64, extended_precision) {
        success(unit) => {},
        failure(error) => { return 13 }
    }
    if extended_writer.len() != 62usize ||
       extended_storage[0usize] != 0x30u8 ||
       extended_storage[1usize] != 0x2eu8 ||
       extended_storage[2usize] != 0x35u8 {
        return 14
    }
    i = 3usize
    while i < 62usize {
        if extended_storage[i] != 0x30u8 { return 15 }
        i += 1usize
    }

    let tiny_f32 = f32.from_bits(1u32)
    var tiny_f32_options = fmt.spec()
    tiny_f32_options.precision = present(45usize)
    var tiny_f32_storage = [0u8; 64]
    var tiny_f32_writer = fmt.buffer_writer(mut tiny_f32_storage)
    match capture fmt.write_with(mut tiny_f32_writer, tiny_f32, tiny_f32_options) {
        success(unit) => {},
        failure(error) => { return 16 }
    }
    if tiny_f32_writer.len() != 47usize ||
       tiny_f32_storage[46usize] != 0x31u8 {
        return 17
    }
    i = 2usize
    while i < 46usize {
        if tiny_f32_storage[i] != 0x30u8 { return 18 }
        i += 1usize
    }

    var short_storage = [0u8; 3]
    var short_writer = fmt.buffer_writer(mut short_storage)
    var short_options = fmt.spec()
    short_options.precision = present(8usize)
    match capture fmt.write_with(mut short_writer, 2.5f64, short_options) {
        success(unit) => { return 19 },
        failure(error) => {}
    }

    let not_a_number = 0.0f64 / 0.0f64
    var special = fmt.spec()
    special.plus = true
    if !display_is(not_a_number, special, "+NaN") ||
       !display_is(1.0f64 / 0.0f64, two_digits, "inf") {
        return 20
    }
    0
}
