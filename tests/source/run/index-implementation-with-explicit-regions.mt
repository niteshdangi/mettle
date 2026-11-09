
module core { pub module ops {
 pub interface Index<I> { type Output; fn index(read i: I): read Self.Output from self; }
} }
type Arr { a: i32; b: i32 }
extend Arr implements core.ops.Index<usize> {
    type Output = i32
    fn index<region r>(receiver read self: Self from r, read i: usize): read i32 from r {
        if i == 0usize { read self.a } else { read self.b }
    }
}
fn main(): i32 { let x = Arr(1, 2); if x[1usize] == 2 { 0 } else { 1 } }
