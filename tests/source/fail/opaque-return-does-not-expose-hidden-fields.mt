// expect-error: name 7:13 field

interface Readable { fn value(): i32; }
copy type Number { value: i32 }
extend Number implements Readable { fn value(): i32 { self.value } }
fn make(): some Readable { Number(42) }
fn main() { make().value }
