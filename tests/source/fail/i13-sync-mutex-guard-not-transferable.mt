// expect-error: type 11:3 unsatisfied interface bound 'Transferable'
import std.sync.mutex
fn send<T: Transferable>(value: take T): Unit {}
fn main(): i32 {
  let lock = mutex.new(1)
  let locked = capture lock.lock()
  let guard = match take locked {
    success(value) => value,
    failure(error) => error.into_inner()
  }
  send(guard)
  0
}
