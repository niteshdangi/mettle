// expect-error-count: 1
// expect-error: type 6:3 recursive by-value product has no finite layout
fn main(){0}
type A {
  x: i32
  b: [A; 2]
}
