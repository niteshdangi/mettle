// expect-exit: 0
// Float holes print the shortest decimal that reads back as the same value, in
// plain positional notation; user types with a Display implementation fill
// holes through the same path as primitives.
import core::fmt::{Message, Display, Debug, Formatter, Write, Error};
import core::fmt::{buffer_writer, formatter, spec};

fn emit(message: format Message, buffer: mut [u8]): usize {
    var out = buffer_writer(mut buffer)
    let ignored = capture message.write_to(mut out)
    out.len()
}

fn same(buffer: read [u8], length: usize, expected: read Text): bool {
    let want = expected.as_bytes()
    if length != want.len() { return false }
    var i = 0usize
    while i < length {
        if buffer[i] != want[i] { return false }
        i += 1usize
    }
    true
}

type Meters { value: i32 }
impl Meters implements Display {
    fn fmt<W: Write>(f: mut Formatter<W>): Unit throws Error {
        try f.write_str("m=")
        try <i32 implements Display>::fmt(self.value, mut f)
    }
}

fn main(): i32 {
    var buffer = [0u8; 512]
    let a = 1.5f64
    let n1 = emit(f"{a} {0.1f64} {100.0f64} {-2.25f32}", mut buffer)
    if !same(read buffer, n1, "1.5 0.1 100 -2.25") { return 1 }
    let tenth = 0.1f32
    let big = 16777216.0f32
    let n2 = emit(f"{tenth}|{big}|{1000000.0f64}|{0.000001f64}|{3.14159f64}", mut buffer)
    if !same(read buffer, n2, "0.1|16777216|1000000|0.000001|3.14159") { return 2 }
    let zero = 0.0f64
    let n3 = emit(f"{zero}|{-zero}|{1.0f64 / zero}|{-1.0f64 / zero}|{zero / zero}", mut buffer)
    if !same(read buffer, n3, "0|-0|inf|-inf|NaN") { return 3 }
    let third = 1.0f64 / 3.0f64
    let n4 = emit(f"{third} {2.0f64 / 3.0f64} {0.30000000000000004f64}", mut buffer)
    if !same(read buffer, n4, "0.3333333333333333 0.6666666666666666 0.30000000000000004") { return 4 }
    let huge = 1e21f64
    let n5 = emit(f"{huge}", mut buffer)
    if !same(read buffer, n5, "1000000000000000000000") { return 5 }
    let tiny: f64 = 5e-324
    let n6 = emit(f"{tiny}", mut buffer)
    if n6 != 326usize || buffer[325usize] != 0x35u8 || buffer[1usize] != 0x2eu8 { return 6 }
    let most: f64 = 1.7976931348623157e308
    let n7 = emit(f"{most}", mut buffer)
    if n7 != 309usize || buffer[0usize] != 0x31u8 || buffer[1usize] != 0x37u8 || buffer[308usize] != 0x30u8 { return 7 }
    let n8 = emit(f"{Meters(42)} {Meters(-7)}!", mut buffer)
    if !same(read buffer, n8, "m=42 m=-7!") { return 8 }
    var out = buffer_writer(mut buffer)
    var f = formatter(mut out, spec())
    let first = capture <f64 implements Debug>::fmt(1.0f64, mut f)
    let second = capture <f32 implements Debug>::fmt(0.5f32, mut f)
    let n9 = out.len()
    if !same(read buffer, n9, "1.00.5") { return 9 }
    0
}
