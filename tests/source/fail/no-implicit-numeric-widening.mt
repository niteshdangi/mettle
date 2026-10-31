// expect-error: type 7:20 expected i64, found i32

fn accept_wide(value: i64): i64 { value }

fn main(): i32 {
    let narrow = 42i32
    if accept_wide(narrow) == 42i64 { 0 } else { 1 }
}
