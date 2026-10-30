// expect-error: type 5:5 expected fn(read i32)

fn value(input: i32): i32 { input }
fn main(): i32 {
    let pointer: fn(read i32): i32 = value
    pointer(42)
}
