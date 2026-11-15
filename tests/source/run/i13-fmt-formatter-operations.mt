// profiles: debug release
// Formatter options (width, precision, fill, alignment, sign and zero flags),
// pad/pad_integral, debug builders, write_str/write_char/write_fmt, custom sinks.

import alloc.string.String
import alloc.hash_map
import core.clone.Clone
import core.fmt
import core.fmt.{Align, Display, Error, Formatter, Spec, Write}
import core.slice
import std.sync.condition
import std.sync.mpsc

type Tally { bytes: usize }
extend Tally implements Write {
    mut fn write_str(read text: Text): Unit throws Error { self.bytes += text.len() }
}

type Wide { value: u8 }
extend Wide implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try f.pad_integral(true, "0x", "ff") }
}

type Probe { a: i32; b: i32 }
extend Probe implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        if f.alternate() { try f.write_str("alt:") }
        var s = try f.debug_struct("Probe")
        try s.field("a", self.a)
        try s.field("b", self.b)
        try s.finish()
        try f.write_char('!')
        try f.write_fmt(f"{self.a}")
    }
}

type Shape { a: i32; b: i32 }
extend Shape implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        var l = try f.debug_list()
        try l.entry(self.a)
        try l.entry(self.b)
        try l.finish()
    }
}

type Pair { a: i32; b: i32 }
extend Pair implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        var t = try f.debug_tuple("Pair")
        try t.field(self.a)
        try t.field(self.b)
        try t.finish()
    }
}

type Table { k: i32 }
extend Table implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        var m = try f.debug_map()
        try m.entry(self.k, self.k)
        try m.finish()
    }
}

type Opaque { value: i32 }

fn increment(value: i32): i32 { value + 1 }
fn is_core_error<T: core.error.Error>(read value: T): bool { true }

fn function_address<F: core.ops.FnPtr>(value: F): usize {
    core.intrinsics.fn_addr(value)
}

fn opts(fill: char, align: Align, width: usize?, precision: usize?, plus: bool, zero: bool, alt: bool): Spec {
    Spec(fill, align, width, precision, plus, false, alt, zero)
}

fn show_text(read value: Text, options: Spec): String { show(String(value), options) }

fn show_slice_escape(read bytes: [u8]): String { show(bytes.escape_ascii(), fmt.spec()) }

fn show_int(value: i32, options: Spec): String {
    var out = String("")
    match capture fmt.write_with(mut out, value, options) {
        success(_) => {},
        failure(_) => { panic("integer formatting failed") }
    }
    out
}

fn show_lower_exp<T: fmt.LowerExp>(read value: T, options: Spec): String {
    var out = String("")
    var formatter = fmt.formatter(mut out, options)
    match capture T.(fmt.LowerExp).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { panic("lower exponent formatting failed") }
    }
    out
}

fn show_upper_exp<T: fmt.UpperExp>(read value: T, options: Spec): String {
    var out = String("")
    var formatter = fmt.formatter(mut out, options)
    match capture T.(fmt.UpperExp).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { panic("upper exponent formatting failed") }
    }
    out
}

fn show_pointer<P: fmt.Pointer>(value: P, options: Spec): String {
    var out = String("")
    var formatter = fmt.formatter(mut out, options)
    match capture P.(fmt.Pointer).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { panic("pointer formatting failed") }
    }
    out
}

fn show_callable_pointer<F: core.ops.FnPtr + fmt.Pointer>(value: F, options: Spec): String {
    var out = String("")
    var formatter = fmt.formatter(mut out, options)
    match capture F.(fmt.Pointer).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { panic("function pointer formatting failed") }
    }
    out
}

fn show_pointer_address(address: usize, options: Spec): String {
    var out = String("")
    var formatter = fmt.formatter(mut out, options)
    match capture fmt.fmt_pointer(mut formatter, address) {
        success(_) => {},
        failure(_) => { panic("pointer address formatting failed") }
    }
    out
}

fn show<T: Display>(read value: T, options: Spec): String {
    var out = String("")
    match capture fmt.write_with(mut out, value, options) {
        success(_) => {},
        failure(_) => { panic("formatting failed") }
    }
    out
}

fn show_debug<T: fmt.Debug>(read value: T, options: Spec): String {
    var out = String("")
    var formatter = fmt.formatter(mut out, options)
    match capture T.(fmt.Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { panic("debug formatting failed") }
    }
    out
}

fn is_text(actual: String, read expected: Text): bool { actual.as_text() == expected }

fn checks_padding(): i32 {
    var sink = String("")
    let options = opts('*', Align.Center, present(6usize), present(3usize), false, false, false)
    var formatter = fmt.formatter(mut sink, options)
    if formatter.align() != Align.Center || formatter.fill() != '*' { return 7 }
    if formatter.width() != present(6usize) || formatter.precision() != present(3usize) { return 8 }
    if Align.Center.clone() != Align.Center { return 9 }
    let right = show_text("ab", opts(' ', Align.Right, present(5usize), none, false, false, false))
    if !is_text(right, "   ab") { return 1 }
    let left = show_text("ab", opts('*', Align.Left, present(4usize), none, false, false, false))
    if !is_text(left, "ab**") { return 2 }
    let center = show_text("ab", opts('*', Align.Center, present(6usize), none, false, false, false))
    if !is_text(center, "**ab**") { return 3 }
    let truncated = show_text("abcdef", opts(' ', Align.Unknown, none, present(3usize), false, false, false))
    if !is_text(truncated, "abc") { return 4 }
    let both = show_text("abcdef", opts(' ', Align.Right, present(5usize), present(2usize), false, false, false))
    if !is_text(both, "   ab") { return 5 }
    let plain = show_text("ab", opts(' ', Align.Unknown, none, none, false, false, false))
    if !is_text(plain, "ab") { return 6 }
    0
}

fn checks_numeric_flags(): i32 {
    let positive = show_int(5i32, opts(' ', Align.Unknown, none, none, true, false, false))
    if !is_text(positive, "+5") { return 10 }
    let negative = show_int(-42i32, opts(' ', Align.Right, present(6usize), none, false, true, false))
    if !is_text(negative, "-00042") { return 11 }
    let signed_zero = show_int(7i32, opts(' ', Align.Unknown, present(4usize), none, true, true, false))
    if !is_text(signed_zero, "+007") { return 12 }
    let plain_hex = show(Wide(255u8), opts(' ', Align.Unknown, none, none, false, false, false))
    if !is_text(plain_hex, "ff") { return 13 }
    let prefixed = show(Wide(255u8), opts(' ', Align.Right, present(6usize), none, false, false, true))
    if !is_text(prefixed, "  0xff") { return 14 }
    let zeroed = show(Wide(255u8), opts(' ', Align.Unknown, present(6usize), none, false, true, true))
    if !is_text(zeroed, "0x00ff") { return 15 }
    0
}

fn checks_exponent_and_pointer_formatting(): i32 {
    let default = show_lower_exp(1234i128, fmt.spec())
    if !is_text(default, "1.234e3") { return 50 }
    let stripped = show_lower_exp(1000i128, fmt.spec())
    if !is_text(stripped, "1e3") { return 51 }
    let tie_even = show_lower_exp(125i128, opts(' ', Align.Unknown, none, present(1usize), false, false, false))
    if !is_text(tie_even, "1.2e2") { return 52 }
    let tie_odd = show_lower_exp(135i128, opts(' ', Align.Unknown, none, present(1usize), false, false, false))
    if !is_text(tie_odd, "1.4e2") { return 53 }
    let carry = show_lower_exp(999i128, opts(' ', Align.Unknown, none, present(0usize), false, false, false))
    if !is_text(carry, "1e3") { return 54 }
    let uppercase = show_upper_exp(-1234i128, fmt.spec())
    if !is_text(uppercase, "-1.234E3") { return 55 }
    let zero = core.ptr.null_mut<u8>()
    let pointer = show_pointer(zero, fmt.spec())
    if !is_text(pointer, "0x0") { return 56 }
    let padded = show_pointer(zero, opts(' ', Align.Unknown, present(8usize), none, true, true, false))
    if !is_text(padded, "0x000000") { return 57 }
    let function: fn(i32): i32 = increment
    let address = function_address(function)
    let function_pointer = show_callable_pointer(function, fmt.spec())
    let expected_pointer = show_pointer_address(address, fmt.spec())
    if function_pointer.as_text() != expected_pointer.as_text() { return 58 }
    let function_debug = show_debug(function, fmt.spec())
    if function_debug.as_text() != function_pointer.as_text() { return 59 }
    let escaped_char = show('\n'.escape_default(), fmt.spec())
    if !is_text(escaped_char, "\\n") { return 66 }
    let escaped_text = show("\n".escape_default(), fmt.spec())
    if !is_text(escaped_text, "\\n") { return 67 }
    0
}

fn checks_builders(): i32 {
    let probe = show(Probe(1i32, 2i32), opts(' ', Align.Unknown, none, none, false, false, false))
    if !is_text(probe, "Probe { a: 1, b: 2 }!1") { return 20 }
    let alt = show(Probe(3i32, 4i32), opts(' ', Align.Unknown, none, none, false, false, true))
    if !is_text(alt, "alt:Probe {\n    a: 3,\n    b: 4,\n}!3") { return 21 }
    let list = show(Shape(1i32, 2i32), opts(' ', Align.Unknown, none, none, false, false, false))
    if !is_text(list, "[1, 2]") { return 22 }
    let tuple = show(Pair(1i32, 2i32), opts(' ', Align.Unknown, none, none, false, false, false))
    if !is_text(tuple, "Pair(1, 2)") { return 23 }
    let map = show(Table(9i32), opts(' ', Align.Unknown, none, none, false, false, false))
    if !is_text(map, "{9: 9}") { return 24 }
    match capture checks_debug_set() {
        success(code) => { if code != 0 { return code } },
        failure(_) => { return 26 }
    }
    match capture checks_builder_extensions() {
        success(code) => { if code != 0 { return code } },
        failure(_) => { return 32 }
    }
    let formatters = checks_type_debug_formatters()
    if formatters != 0 { return formatters }
    0
}

fn checks_debug_set(): i32 throws Error {
    var output = String("")
    var formatter = fmt.formatter(mut output, fmt.spec())
    var set = try formatter.debug_set()
    try set.entry(1i32)
    try set.entry(2i32)
    try set.finish()
    if output.as_text() != "{1, 2}" { return 25 }
    0
}

fn checks_builder_extensions(): i32 throws Error {
    {
        var output = String("")
        var formatter = fmt.formatter(mut output, fmt.spec())
        var structure = try formatter.debug_struct("Record")
        try structure.field("value", 7i32)
        try structure.finish_non_exhaustive()
        if output.as_text() != "Record { value: 7, .. }" { return 27 }
    }
    {
        var output = String("")
        var formatter = fmt.formatter(mut output, fmt.spec())
        var tuple = try formatter.debug_tuple("")
        try tuple.finish_non_exhaustive()
        if output.as_text() != "(..)" { return 28 }
    }
    {
        var output = String("")
        var formatter = fmt.formatter(mut output, fmt.spec())
        var list = try formatter.debug_list()
        try list.entries([1i32, 2i32])
        try list.finish_non_exhaustive()
        if output.as_text() != "[1, 2, ..]" { return 29 }
    }
    {
        var output = String("")
        var formatter = fmt.formatter(mut output, fmt.spec())
        var set = try formatter.debug_set()
        try set.finish_non_exhaustive()
        if output.as_text() != "{..}" { return 30 }
    }
    {
        var output = String("")
        var formatter = fmt.formatter(mut output, fmt.spec())
        var map = try formatter.debug_map()
        try map.entries([(1i32, 2i32)])
        try map.finish_non_exhaustive()
        if output.as_text() != "{1: 2, ..}" { return 31 }
    }
    0
}

fn checks_type_debug_formatters(): i32 {
    if !is_core_error(Error()) { return 80 }
    if !is_text(show_debug(mpsc.SendError(Opaque(1i32)), fmt.spec()), "SendError { .. }") { return 88 }
    if !is_text(show_debug(mpsc.TrySendError(Opaque(1i32), false), fmt.spec()), "TrySendError { .. }") { return 89 }
    let borrowed_channel = mpsc.channel<i32>()
    if !is_text(show_debug(borrowed_channel.1.iter(), fmt.spec()), "Iter { .. }") { return 86 }
    let owned_channel = mpsc.channel<i32>()
    if !is_text(show_debug(owned_channel.1.into_iter(), fmt.spec()), "IntoIter { .. }") { return 87 }
    let condition_variable = condition.new()
    let timeout_mutex = std.sync.mutex.new(false)
    let guard = match take capture timeout_mutex.lock() {
        success(guard) => guard,
        failure(error) => error.into_inner()
    }
    let waited = capture condition_variable.wait_timeout(guard, std.time.from_nanos(0u64))
    let timed_out = match take waited {
        success(pair) => pair.1,
        failure(error) => error.into_inner().1
    }
    let timed_out = show_debug(timed_out, fmt.spec())
    if !is_text(timed_out, "TimedOut { timed_out: true }") { return 69 }
    let pinned_value = show_debug(core.marker.PhantomPinned, fmt.spec())
    if !is_text(pinned_value, "PhantomPinned") { return 68 }
    let range = show_debug(core.iter.range_from(3i32), fmt.spec())
    if !is_text(range, "RangeFrom { start: 3, done: false }") { return 61 }
    let bytes = [65u8, 10u8, 255u8]
    let escaped = show_slice_escape(read bytes)
    if !is_text(escaped, "A\\n\\xff") { return 62 }
    let slice_debug = show_debug(bytes.escape_ascii(), fmt.spec())
    if !is_text(slice_debug, "SliceEscapeAscii { rest: [65, 10, 255], current: none }") { return 63 }
    let utf16 = show_debug(core.char.decode_utf16(core.iter.once(0xd800u16)), fmt.spec())
    if !is_text(utf16, "DecodeUtf16 { iter: Once { value: present(55296) }, buffered: none }") { return 64 }
    let lowercase = show("HÉLLO".lowercase_chars(), fmt.spec())
    if !is_text(lowercase, "héllo") { return 78 }
    let uppercase = show("Straße".uppercase_chars(), fmt.spec())
    if !is_text(uppercase, "STRASSE") { return 79 }
    var left = hash_map.set_new<i32>()
    let _ = left.insert(1i32)
    var right = hash_map.set_new<i32>()
    let _ = right.insert(2i32)
    let algebra = show_debug(left.`union`(read right), fmt.spec())
    if !is_text(algebra, "Union { left: {1}, right: {2}, side: 0, index: 0 }") { return 65 }
    let values = [1i32, 0i32, 2i32]
    let split = show_debug(values.split(fn(read value: i32): bool { value == 0i32 }), fmt.spec())
    if !is_text(split, "Split { items: [1, 0, 2], from_back: false, inclusive: false, .. }") { return 66 }
    let split_n = show_debug(values.rsplitn(2usize, fn(read value: i32): bool { value == 0i32 }), fmt.spec())
    if !is_text(split_n, "RSplitN { items: [1, 0, 2], remaining: 2, .. }") { return 67 }
    let array_iter = core.iter.into_iterator([Opaque(1i32), Opaque(2i32)])
    let array_iter_debug = show_debug(array_iter, fmt.spec())
    if !is_text(array_iter_debug, "ArrayIntoIter { remaining: 2, .. }") { return 68 }
    0
}

fn checks_sinks(): i32 {
    var tally = Tally(0usize)
    match capture fmt.write(mut tally, 12345i32) {
        success(_) => {},
        failure(_) => { return 30 }
    }
    if tally.bytes != 5usize { return 31 }

    var text = String("")
    match capture text.write_char('\u{e9}') {
        success(_) => {},
        failure(_) => { return 32 }
    }
    if text.len() != 2usize || !is_text(text, "\u{e9}") { return 33 }
    0
}

fn literal_only(message: format fmt.Message): bool {
    match message.as_str() {
        present(text) => text == "plain",
        none => false
    }
}

fn checks_arguments(): i32 {
    if !literal_only(f"plain") { return 40 }
    let value = 3i32
    if literal_only(f"n={value}") { return 41 }
    0
}

fn checks_borrow_errors(): i32 {
    let shared_cell = core.cell.RefCell.new(1i32)
    var shared_guard = shared_cell.borrow()
    match shared_cell.try_borrow_mut() {
        success(_) => { return 70 },
        failure(error) => {
            if !is_text(show_debug(error, fmt.spec()), "BorrowMutError") { return 71 }
            if !is_text(show(error, fmt.spec()), "already borrowed") { return 72 }
        }
    }
    if *shared_guard.get_ref() != 1i32 { return 73 }

    let exclusive = core.cell.RefCell.new(1i32)
    var exclusive_guard = exclusive.borrow_mut()
    match exclusive.try_borrow() {
        success(_) => { return 74 },
        failure(error) => {
            if !is_text(show_debug(error, fmt.spec()), "BorrowError") { return 75 }
            if !is_text(show(error, fmt.spec()), "already mutably borrowed") { return 76 }
        }
    }
    if *exclusive_guard.get_mut() != 1i32 { return 77 }
    0
}

fn main(): i32 {
    let first = checks_padding()
    if first != 0 { return first }
    let second = checks_numeric_flags()
    if second != 0 { return second }
    let exponent = checks_exponent_and_pointer_formatting()
    if exponent != 0 { return exponent }
    let fourth = checks_arguments()
    if fourth != 0 { return fourth }
    let borrow_errors = checks_borrow_errors()
    if borrow_errors != 0 { return borrow_errors }
    let third = checks_builders()
    if third != 0 { return third }
    checks_sinks()
}
