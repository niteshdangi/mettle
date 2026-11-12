// expect-error: type 12:5 unsatisfied interface obligation
// expect-error-count: 1
import alloc.arc
import std.io.{Error, Reader}
type StaticOnly {}
extend read StaticOnly from static implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error { 0usize }
}
fn require_reader<R: Reader>(mut reader: R): Unit {}
fn main(): i32 {
    var reader = arc.new(StaticOnly())
    require_reader(mut reader)
    0
}
