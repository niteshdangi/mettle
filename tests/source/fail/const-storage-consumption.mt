// profiles: debug release
// expect-error: constant 9:5 constant value is not fully initialized
// expect-error: constant 16:5 constant value is not fully initialized
// expect-error-count: 2

const fn reuse_extracted(): i32 {
    let cell = core.cell.UnsafeCell.new(7i32)
    let first = cell.into_inner()
    cell.into_inner()
}

type Payload { value: i32 }
const fn reuse_moved(): i32 {
    let value = Payload(7i32)
    let first = core.cell.UnsafeCell.new(value)
    core.cell.UnsafeCell.new(value).into_inner().value
}
const EXTRACTED: i32 = reuse_extracted()
const MOVED: i32 = reuse_moved()
fn main(): i32 { 0 }
