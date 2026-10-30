// expect-error: type
// An immutable static is shared by every thread, so it must be Shareable.
static COUNTER: core.cell.Cell<i32> = core.cell.Cell.new(0)

fn main(): i32 { 0 }
