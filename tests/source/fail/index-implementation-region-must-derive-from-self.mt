// expect-error: region 9:56 view region or invariant payload does not satisfy

module core { pub module ops {
 pub interface Index<I> { type Output; fn index(read i: I): read Self.Output from self; }
} }
type Arr { a: i32; b: i32 }
extend Arr implements core.ops.Index<usize> {
    type Output = i32
    fn index<region r>(read i: usize): read i32 from r { read self.a }
}
fn main(): i32 { 0 }
