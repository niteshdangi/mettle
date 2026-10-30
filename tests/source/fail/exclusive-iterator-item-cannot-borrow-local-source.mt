// expect-error: ownership 16:5 returned view escapes local storage

type Bag { a: i32; b: i32 }
type Cursor<region r> { bag: mut Bag from r; at: i32 }
impl<region r> Cursor<region r> {
    mut fn next(): (mut i32 from r)? {
        let i = self.at
        self.at += 1
        if i == 0 { present(mut self.bag.a) } else if i == 1 { present(mut self.bag.b) } else { none }
    }
}

fn bad(c: mut Bag): (mut i32 from c)? {
    var own = Bag(1, 2)
    var it = Cursor(mut own, 0)
    it.next()
}
fn main(): i32 { 0 }
