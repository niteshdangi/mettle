// expect-error-count: 1
// expect-error: type 5:5 VaList construction requires a compiler-owned variadic frame
import core.ffi.VaList
fn construct<region frame>(): VaList<region frame> {
    VaList<region frame>()
}
fn main(): i32 { 0 }
