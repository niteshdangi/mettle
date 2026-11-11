// expect-error: region 5:5 view region or invariant payload
fn invalid<region r>(read source: i32 from r): [read i32 from r; 2] {
    let value = 1
    let values = [read source, read value]
    return values
}
fn main(): i32 { 0 }
