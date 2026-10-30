
interface Total { fn value(): i32; }
impl [i32] implements Total {
    fn value(): i32 {
        var result = 0
        for value in self { result += value }
        result
    }
}
fn erase(values: read [i32]): read any Total from values { read values }
fn main() {
    let values = [20,22]
    let slice: read [i32] = read values
    let erased = erase(slice)
    if erased.value() == 42 { 0 } else { 1 }
}
