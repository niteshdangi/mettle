// expect-error-count: 1
// expect-error: name 11:18 ambiguous macro import
module left {
    pub macro pick { () => { 1i32 }; }
}
module right {
    pub macro pick { () => { 2i32 }; }
}
import left.pick as selection
import right.pick as selection
fn main(): i32 { selection!() }
