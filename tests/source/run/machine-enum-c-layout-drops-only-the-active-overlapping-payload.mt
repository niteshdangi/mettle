
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
@layout(C)
enum Choice { Empty; One(Counted); Two(Counted,Counted) }
fn main() {
    var count = 0
    let counter = core.ptr.from_mut(count)
    { let value = Choice.One(Counted(counter,10)) }
    { let value = Choice.Two(Counted(counter,1),Counted(counter,31)) }
    { let value = Choice.Empty }
    if count == 42 && core.mem.size_of<Choice>() == 40usize { 0 } else { 1 }
}
