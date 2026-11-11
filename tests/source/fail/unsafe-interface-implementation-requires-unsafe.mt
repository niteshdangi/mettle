// expect-error: unsafe 4:1 unsafe interface implementation requires an unsafe extend
unsafe interface Provider { fn value(): i32; unsafe fn release(): Unit; }
type Bad {}
extend Bad implements Provider {
    fn value(): i32 { 0 }
    unsafe fn release(): Unit { () }
}
fn main(): i32 { 0 }
