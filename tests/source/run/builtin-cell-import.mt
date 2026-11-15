import core.cell.Cell

fn main(): i32 {
    let value: Cell<u64> = Cell.new(42u64)
    if value.get() == 42u64 { 0 } else { 1 }
}
