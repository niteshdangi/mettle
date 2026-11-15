// expect-error-count: 1
// expect-error: type 6:5 generic argument does not satisfy Copy
import core.ffi.VaList
fn copy_value<T: Copy>(value: T): T { value }
fn duplicate<region frame>(take cursor: VaList<region frame>): VaList<region frame> {
    copy_value(cursor)
}
fn main(): i32 { 0 }
