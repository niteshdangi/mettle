
module core { pub module ops {
    pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: usize): read Self::Output from self; }
    pub interface IndexRangeMut { type Output: unsized; mut fn index_range_mut(start: usize, end: usize): mut Self::Output from self; }
} }
type Buf { cells: [i32; 4] }
impl Buf implements core::ops::IndexRange {
    type Output = [i32]
    fn index_range(start: usize, end: usize): read [i32] from self {
        let stop = if end > 4usize { 4usize } else { end }
        read self.cells[start..stop]
    }
}
impl Buf implements core::ops::IndexRangeMut {
    type Output = [i32]
    mut fn index_range_mut(start: usize, end: usize): mut [i32] from self {
        let stop = if end > 4usize { 4usize } else { end }
        mut self.cells[start..stop]
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
    0
}
