
type Bag { a: i32; b: i32 }
type Cursor<region r> { bag: mut Bag from r; at: i32 }
extend<region r> Cursor<region r> {
    mut fn next(): (mut i32 from r)? {
        let i = self.at
        self.at += 1
        if i == 0 { present(mut self.bag.a) } else if i == 1 { present(mut self.bag.b) } else { none }
    }
}

fn first_mut(mut c: Bag): (mut i32 from c)? {
    var it = Cursor(mut c, 0)
    it.next()
}
fn main(): i32 {
    var bag = Bag(1, 2)
    match take first_mut(mut bag) { present(x) => { *x += 5 }, none => { return 1 } }
    if bag.a == 6 && bag.b == 2 { 0 } else { 2 }
}
