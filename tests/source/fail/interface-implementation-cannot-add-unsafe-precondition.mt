// expect-error: type 5:12 implementation method contract does not match interface
interface Raw { fn release(): Unit; }
type Bad {}
extend Bad implements Raw {
    unsafe fn release(): Unit { () }
}
fn main(): i32 { 0 }
