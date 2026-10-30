// expect-error: ownership 12:5 live read loan

type Hold<region r> { x: read i32 from r }
interface Put { fn put<region r>(h: mut Hold<region r>, v: read i32 from r): Unit; }
type A {}
impl A implements Put { fn put<region r>(h: mut Hold<region r>, v: read i32 from r): Unit { h.x = read v } }
fn run<P: Put>(p: read P): i32 {
    var a = 1
    var h = Hold(read a)
    var b = 2
    p.put(mut h, read b)
    b = 3
    *h.x
}
fn main(): i32 { run(read A()) }
