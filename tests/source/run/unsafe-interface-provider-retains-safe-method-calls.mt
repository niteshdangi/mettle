unsafe interface Provider { fn value(): i32; unsafe fn release(): Unit; }
type Good {}
unsafe extend Good implements Provider {
    fn value(): i32 { 42 }
    fn release(): Unit { () }
}
fn main(): i32 {
    let owner = Good()
    unsafe { Good.(Provider).release(owner) }
    owner.value() - 42
}
