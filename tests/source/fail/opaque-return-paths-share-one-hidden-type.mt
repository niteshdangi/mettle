// expect-error: type 10:5 different hidden types

interface Readable { fn value(): i32; }
type Number {}
type Other {}
extend Number implements Readable { fn value(): i32 { 42 } }
extend Other implements Readable { fn value(): i32 { 42 } }
fn make(flag: bool): some Readable {
    if flag { return Number() }
    return Other()
}
fn main() { 0 }
