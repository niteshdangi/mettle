
type Bag { n: i32 }
impl Bag {
    mut fn add(item: take i32) { self.n += item }
}
fn gen<T>(x: take T): T { x }
fn first(v: read [i32; 3]): read i32 from v { read v[0] }
fn main(): i32 {
    let arr = [1, 2, 3]
    let r = first(read arr)
    var b = Bag(0)
    b.add(*r)
    let g = gen(*r)
    b.n + g - 2
}
