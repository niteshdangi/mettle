// expect-error-count: 1
// expect-error: type 3:10 recursive by-value product has no finite layout
enum E { X(E), Y }
fn main(){0}
