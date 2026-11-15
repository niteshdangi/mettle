// expect-error-count: 1
// expect-error: region 6:26 view region or invariant payload does not satisfy its declared relationship
import core.ffi.VaList
fn escape<region frame>(
    take cursor: VaList<region frame>
): VaList<region static> {
    cursor
}
fn main(): i32 { 0 }
