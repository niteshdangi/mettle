// expect-error: region 6:5 interface bound does not hold after region inference
interface SameRegion {}
extend<region r> (core.cell.Cell<read i32 from r>, core.cell.Cell<read i32 from r>) implements SameRegion {}
fn require<R: SameRegion>(read value: R) {}
fn reject<region a, region b>(take first: core.cell.Cell<read i32 from a>, take second: core.cell.Cell<read i32 from b>) {
    require(read (take first, take second))
}
fn main(): i32 { 0 }
