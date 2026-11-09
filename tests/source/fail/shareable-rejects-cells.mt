// expect-error: type 5:3 unsatisfied interface bound 'Shareable'
type Cellular { c: core.cell.Cell<i32> }
fn share<T: Shareable>(value: read T): Unit {}
fn main(): i32 {
  share(Cellular(core.cell.Cell.new(1)))
  0
}
