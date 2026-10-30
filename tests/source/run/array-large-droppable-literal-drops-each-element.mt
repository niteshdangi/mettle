
type G { counter: ptr<mut i32>; drop { unsafe { *self.counter += 1 } } }
fn main(): i32 {
    var count = 0
    let c = core::ptr::from_mut(count)
    {
        let a = [G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c), G(c)]
    }
    if count == 100 { 0 } else { 1 }
}
