// expect-error: type 3:38 unsatisfied interface bound 'Transferable'
fn send<T: Transferable>(take value: T): Unit {}
fn forward<T>(take value: T): Unit { send(value) }
fn main(): i32 { 0 }
