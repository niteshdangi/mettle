// expect-error-count: 1
// expect-error: type 3:10 recursive by-value product has no finite layout
type A { value: (i32,A) }
fn main(){0}
