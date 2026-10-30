// expect-error-count: 1
// expect-error: type 4:10 recursive by-value product has no finite layout
enum E { X(i32), Y(A) }
type A { e: E }
fn main(){0}
