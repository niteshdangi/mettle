// expect-error: ownership 10:5 live read loan

copy type Pair { first: i32; second: i32 }
extern "C" {
    unsafe fn forward(value: read Pair): read Pair from value;
}
fn main() {
    var value = Pair(20,22)
    let result = unsafe { forward(value) }
    value.first = 40
    result.first + result.second
}
