
type Counted {
    counter: ptr<mut i32>; amount: i32
    drop { unsafe { *self.counter += self.amount } }
}
fn main() {
    var count = 0
    let counter = core.ptr.from_mut(count)
    {
        let cell = core.cell.Cell.new(Counted(counter,1))
        let old = cell.replace(Counted(counter,10))
        cell.set(Counted(counter,100))
        if count != 10 { return 1 }
    }
    if count == 111 { 0 } else { 2 }
}
