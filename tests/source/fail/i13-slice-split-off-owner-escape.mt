// expect-error: ownership 7:5 returned view escapes
fn bad(read source: i32): read i32 from source {
    let values = [10, 20]
    var view: read [i32] = read values[..]
    let first = core.slice.split_off_first(mut view).unwrap()
    let _ = source
    first
}
fn main(): i32 { 0 }
