module core { pub module ops {
    pub copy enum RangeEnd { Unbounded, Exclusive(usize), Inclusive(usize) }
    pub copy enum Fault { Rejected }
    pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: RangeEnd): read Self.Output from self throws Fault; }
} }
type Buf { cells: [i32; 2]; failed: bool }
extend Buf implements core.ops.IndexRange {
    type Output = [i32]
    fn index_range(start: usize, end: core.ops.RangeEnd): read [i32] from self throws core.ops.Fault {
        if self.failed { throw core.ops.Fault.Rejected }
        read self.cells[start..]
    }
}
fn main(): i32 {
    let value = Buf([1, 2], false)
    match take capture (read value[1usize..]) {
        success(selected) => { if selected.len() != 1usize || selected[0] != 2 { return 1 } },
        failure(_) => { return 2 }
    }
    let rejected = Buf([1, 2], true)
    match take capture (read rejected[..]) {
        success(_) => 3,
        failure(core.ops.Fault.Rejected) => 0
    }
}
