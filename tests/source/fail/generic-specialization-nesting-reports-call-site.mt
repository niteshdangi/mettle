// expect-error-count: 1
// expect-error: limit 4:63 generic specialization nesting limit exceeded while instantiating 'deep'
type Wrap<T>{value:T}
fn deep<T>(take value: T, n: i32): i32 { if n == 0 {0} else { deep(Wrap(value), n - 1) } }
fn main(): i32 { deep(1, 2) }
