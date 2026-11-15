// expect-error-count: 1
// expect-error: type 6:5 unsatisfied interface bound 'Transferable'
import core.ffi.VaList
fn transfer<T: Transferable>(take value: T): Unit {}
fn rejected<region frame>(take cursor: VaList<region frame>): Unit {
    transfer(take cursor)
}
fn main(): i32 { 0 }
