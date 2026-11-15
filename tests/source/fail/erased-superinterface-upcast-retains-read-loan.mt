// expect-error: ownership 14:5 live read loan
interface Parent { fn value(): i32; }
interface Child: Parent {}
type Number { value: i32 }
extend Number implements Parent { fn value(): i32 { self.value } }
extend Number implements Child {}
fn parent<region r>(value: read any Child from r): read any Parent from r {
    read value
}
fn main(): i32 {
    var number = Number(42)
    let child: read any Child = read number
    let inherited = parent(child)
    number.value = 7
    inherited.value() - 42
}
