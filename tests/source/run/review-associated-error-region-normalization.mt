// profiles: debug release
import std.io.{Error, ErrorKind}

interface Parse: Sized {
    type Error;
    static fn parse(fail: bool): Self throws Self.Error;
}
type Value { number: i32 }
extend Value implements Parse {
    type Error = std.io.Error
    static fn parse(fail: bool): Value throws std.io.Error {
        if fail { throw std.io.from_kind(ErrorKind.Other) }
        Value(42)
    }
}
fn propagate(fail: bool): i32 throws Error {
    let value = try Value.(Parse).parse(fail)
    value.number
}
fn main(): i32 {
    match take capture propagate(false) {
        success(value) => { if value != 42 { return 1 } },
        failure(_) => { return 2 }
    }
    match take capture propagate(true) {
        success(_) => { return 3 },
        failure(error) => { if !error.kind().is(ErrorKind.Other) { return 4 } }
    }
    0
}
