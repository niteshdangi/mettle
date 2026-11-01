// expect-error: region 10:5 interface bound does not hold after region inference
interface StaticRange {}
type RefRange<T> { value: T }
extend<region r> RefRange<read [i32] from r> implements StaticRange where region r: static {}
fn require<R: StaticRange>(value: read R) {}
fn main(): i32 {
    let values = [1, 2]
    let view: read [i32] = read values
    let range = RefRange(view)
    require(read range)
    0
}
