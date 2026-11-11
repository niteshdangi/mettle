module core { pub module ops {
    pub copy enum RangeEnd { Unbounded, Exclusive(usize), Inclusive(usize) }
    pub interface IndexRange { type Output: unsized; fn index_range(read start: usize, mut end: RangeEnd): read Self.Output from self; }
} }
type Buf { cells: [i32; 4] }
extend Buf implements core.ops.IndexRange {
    type Output = [i32]
    fn index_range(read start: usize, mut end: core.ops.RangeEnd): read [i32] from self {
        end = core.ops.RangeEnd.Exclusive(3usize)
        let stop = match end {
            core.ops.RangeEnd.Exclusive(value) => value,
            _ => 0usize
        }
        read self.cells[start..stop]
    }
}
fn main(): i32 {
    let value = Buf([1, 2, 3, 4])
    let selected: read [i32] = read value[1usize..]
    if selected.len() == 2usize && selected[0] == 2 { 0 } else { 1 }
}
