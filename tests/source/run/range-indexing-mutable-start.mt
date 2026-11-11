module core { pub module ops {
    pub copy enum RangeEnd { Unbounded, Exclusive(usize), Inclusive(usize) }
    pub interface IndexRange { type Output: unsized; fn index_range(mut start: usize, read end: RangeEnd): read Self.Output from self; }
} }
type Buf { cells: [i32; 4] }
extend Buf implements core.ops.IndexRange {
    type Output = [i32]
    fn index_range(mut start: usize, read end: core.ops.RangeEnd): read [i32] from self {
        start += 1usize
        read self.cells[start..3usize]
    }
}
fn main(): i32 {
    let value = Buf([1, 2, 3, 4])
    var start = 0usize
    let selected: read [i32] = read value[start..]
    if start == 1usize && selected.len() == 2usize && selected[0] == 2 { 0 } else { 1 }
}
