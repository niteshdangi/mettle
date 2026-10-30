// expect-error: limit 5:28 specialization nesting limit

copy type Wrapper<T:Copy> { value:T }
fn expand<T:Copy>(value:T,n:i32):i32 {
    if n == 0 { 0 } else { expand(Wrapper(value),n-1) }
}
fn main() { expand(1,2) }
