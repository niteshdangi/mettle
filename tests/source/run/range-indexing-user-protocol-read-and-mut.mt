
module core { pub module ops {
    pub copy enum RangeEnd { Inclusive(usize), Unbounded, Exclusive(usize) }
    pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: RangeEnd): read Self.Output from self; }
    pub interface IndexRangeMut { type Output: unsized; mut fn index_range_mut(start: usize, take end: RangeEnd): mut Self.Output from self; }
} }
type Buf { cells: [i32; 4] }
fn stop(end: core.ops.RangeEnd): usize {
    let largest = !0usize
    match end {
        core.ops.RangeEnd.Unbounded => 4usize,
        core.ops.RangeEnd.Exclusive(value) => if value == largest { 1usize } else if value > 4usize { 4usize } else { value },
        core.ops.RangeEnd.Inclusive(value) => if value == largest { 2usize } else if value == largest - 1usize { 3usize } else if value >= 4usize { 4usize } else { value + 1usize }
    }
}
fn bound(mut calls: i32, digit: i32, value: usize): usize {
    calls = calls * 10 + digit
    value
}
fn generic<T: core.ops.IndexRange<Output = [i32]>>(read value: T): usize {
    let largest = !0usize
    let selected = read value[..largest]
    selected.len()
}
extend Buf implements core.ops.IndexRange {
    type Output = [i32]
    fn index_range(start: usize, end: core.ops.RangeEnd): read [i32] from self {
        read self.cells[start..stop(end)]
    }
}
extend Buf implements core.ops.IndexRangeMut {
    type Output = [i32]
    mut fn index_range_mut(start: usize, take end: core.ops.RangeEnd): mut [i32] from self {
        mut self.cells[start..stop(take end)]
    }
}
fn main(): i32 {
    var b = Buf([1, 2, 3, 4])
    let mid: read [i32] = read b[1..3]
    let tail: read [i32] = read b[2..]
    let head: read [i32] = read b[..=0]
    if mid.len() != 2 || tail.len() != 2 || head.len() != 1 { return 1 }
    let w: mut [i32] = mut b[1..]
    w[0] = 20
    if b.cells[1] != 20 { return 2 }
    let largest = !0usize
    let before_largest = largest - 1usize
    let whole: read [i32] = read b[..]
    let exclusive: read [i32] = read b[..largest]
    let inclusive: read [i32] = read b[..=largest]
    let inclusive_before: read [i32] = read b[..=before_largest]
    if whole.len() != 4usize || exclusive.len() != 1usize ||
       inclusive.len() != 2usize || inclusive_before.len() != 3usize { return 3 }
    if generic(read b) != 1usize { return 8 }
    {
        let bounded: mut [i32] = mut b[..largest]
        if bounded.len() != 1usize { return 4 }
    }
    {
        let inclusive: mut [i32] = mut b[..=before_largest]
        if inclusive.len() != 3usize { return 5 }
    }
    {
        let inclusive: mut [i32] = mut b[..=largest]
        if inclusive.len() != 2usize { return 7 }
    }
    var calls = 0
    let selected: read [i32] = read b[bound(calls, 1, 1usize)..=bound(calls, 2, 2usize)]
    if calls != 12 || selected.len() != 2usize { return 6 }
    0
}
