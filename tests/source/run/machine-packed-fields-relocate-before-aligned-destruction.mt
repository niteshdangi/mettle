
type Leaf {
    counter: ptr<mut i32>; amount: i32
    drop {
        let address = core.ptr.from_ref(self).addr()
        unsafe {
            if address % core.mem.align_of<Leaf>() == 0usize {
                *self.counter += self.amount
            }
        }
    }
}
@packed(1)
type Packed { first: u8; leaf: Leaf; last: Leaf }
fn main() {
    var count = 0
    let counter = core.ptr.from_mut(count)
    { let value = Packed(1u8,Leaf(counter,10),Leaf(counter,32)) }
    if count == 42 { 0 } else { 1 }
}
