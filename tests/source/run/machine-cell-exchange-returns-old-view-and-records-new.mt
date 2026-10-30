
fn exchange<region a>(cell: read core.cell.Cell<read i32 from a>,
                      value: read i32 from a): read i32 from cell {
    cell.replace(read value)
}
fn main() {
    let first = 1
    let second = 42
    let cell = core.cell.Cell.new(read first)
    let old = exchange(cell,read second)
    if *old == 1 && *cell.get() == 42 { 0 } else { 1 }
}
