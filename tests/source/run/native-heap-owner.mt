fn main(): i32 {
    let value: heap i32 = heap 42
    if *value.get() == 42 { 0 } else { 1 }
}
