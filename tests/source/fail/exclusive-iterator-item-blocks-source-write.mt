// expect-error: ownership 16:5 live exclusive loan

type Bag { a: i32; b: i32 }
type Cursor<region r> { bag: mut Bag from r; at: i32 }
extend<region r> Cursor<region r> {
    mut fn next(): (mut i32 from r)? {
        let i = self.at
        self.at += 1
        if i == 0 { present(mut self.bag.a) } else if i == 1 { present(mut self.bag.b) } else { none }
    }
}

fn bad(mut c: Bag): Unit {
    var it = Cursor(mut c, 0)
    let x = it.next()
    c.a = 5
    match take x { present(p) => { *p += 1 }, none => {} }
}
fn main(): i32 { 0 }
