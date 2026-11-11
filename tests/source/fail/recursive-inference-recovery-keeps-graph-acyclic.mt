// expect-error: type 5:18 recursive inferred type
fn inspect<T>(read value: T): Unit { () }
fn bad(flag: bool): Unit {
    let value = none
    let nested = if flag { value } else { present(value) }
    inspect(nested)
}
fn main(): i32 { 0 }
