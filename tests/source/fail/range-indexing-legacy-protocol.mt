// expect-error: type 13:21 range indexing protocol requires bounds usize and core.ops.RangeEnd
module core { pub module ops {
    pub copy enum RangeEnd { Unbounded, Exclusive(usize), Inclusive(usize) }
    pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: usize): read Self.Output from self; }
} }
type Buf { cells: [i32; 1] }
extend Buf implements core.ops.IndexRange {
    type Output = [i32]
    fn index_range(start: usize, end: usize): read [i32] from self { read self.cells[start..end] }
}
fn main(): i32 {
    let value = Buf([1])
    let view = read value[..]
    view.len() as i32
}
