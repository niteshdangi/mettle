interface Show { fn show(): i32; }
type A { v: i32 }
extend A implements Show { fn show(): i32 { self.v } }
fn call<T: unsized + Show>(x: read T): i32 { x.show() }
fn main(): i32 {
    let a = A(4)
    let e: read any Show = read a
    if call(e) != 4 { return 1 }
    0
}
