// expect-error: ownership 12:5 returned view escapes local storage
module core { pub module ops {
    pub copy enum RangeEnd { Unbounded, Exclusive(usize), Inclusive(usize) }
    pub interface IndexRange { type Output: unsized; fn index_range(start: usize, read end: RangeEnd): read Self.Output from end; }
} }
type Buf { value: i32 }
extend Buf implements core.ops.IndexRange {
    type Output = core.ops.RangeEnd
    fn index_range(start: usize, read end: core.ops.RangeEnd): read core.ops.RangeEnd from end { read end }
}
fn bad(read value: Buf): read core.ops.RangeEnd from value {
    read value[..3usize]
}
fn main(): i32 { 0 }
