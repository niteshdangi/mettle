// profiles: debug release
// Formatter options (width, precision, fill, alignment, sign and zero flags),
// pad/pad_integral, debug builders, write_str/write_char/write_fmt, custom sinks.

import alloc.string.String
import core.fmt
import core.fmt.{Align, Display, Error, Formatter, Spec, Write}

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

fn opts(fill: char, align: Align, width: usize?, precision: usize?, plus: bool, zero: bool, alt: bool): Spec {
    Spec(fill, align, width, precision, plus, false, alt, zero)
}

fn show_text(read value: Text, options: Spec): String { show(String(value), options) }

fn show_int(value: i32, options: Spec): String {
    var out = String("")
    match capture fmt.write_with(mut out, value, options) {
        success(_) => {},
        failure(_) => {}
    }
    out
}

fn show<T: Display>(read value: T, options: Spec): String {
    var out = String("")
    match capture fmt.write_with(mut out, value, options) {
        success(_) => {},
        failure(_) => {}
    }
    out
}

fn is_text(actual: String, read expected: Text): bool { actual.as_text() == expected }

fn checks_padding(): i32 {
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

fn main(): i32 {
    let first = checks_padding()
    if first != 0 { return first }
    let second = checks_numeric_flags()
    if second != 0 { return second }
    let fourth = checks_arguments()
    if fourth != 0 { return fourth }
    let third = checks_builders()
    if third != 0 { return third }
    checks_sinks()
}
