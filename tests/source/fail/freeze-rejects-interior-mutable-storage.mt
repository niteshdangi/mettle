// expect-error: type 6:5 generic argument does not satisfy Freeze
// expect-error: type 7:5 generic argument does not satisfy Freeze

fn require_freeze<T: Freeze>(take value: T): Unit {}
fn main(): i32 {
    require_freeze(core.cell.UnsafeCell.new(1i32))
    require_freeze(fn(): i32 { 1 })
    0
}
