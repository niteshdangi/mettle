// expect-error: type 7:18 expected heap i32, found read i32

fn accept_owner(value: heap i32): Unit {}

fn main(): i32 {
    let value = 42
    accept_owner(read value)
    0
}
