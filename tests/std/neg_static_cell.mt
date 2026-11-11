// expect-error: type 3:1 immutable static storage requires a Shareable type
// An immutable static is shared by every thread, so it must be Shareable.
static COUNTER: core.cell.Cell<i32> = core.cell.Cell.new(0)

fn main(): i32 { 0 }
