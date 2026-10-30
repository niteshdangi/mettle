// expect-error: type 3:38 unsatisfied interface bound 'Transferable'
fn send<T: Transferable>(value: take T): Unit {}
fn forward<T>(value: take T): Unit { send(value) }
fn main(): i32 { 0 }
