// expect-error: type 2:1 immutable static storage requires a Shareable type
static STATE: core.cell.RefCell<i32> = core.cell.RefCell.new(0)

fn main(): i32 { 0 }
