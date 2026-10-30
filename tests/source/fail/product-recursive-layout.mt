// expect-error-count: 1
// expect-error: type 4:15 no finite layout
copy type A { b: B }
copy type B { a: A }
fn main() { 0 }
