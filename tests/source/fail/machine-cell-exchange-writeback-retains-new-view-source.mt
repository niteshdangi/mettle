// expect-error: ownership 8:44 access or storage conflicts with a live read loan

fn set<region a>(read cell: core.cell.Cell<read i32 from a>,
                 read value: i32 from a) { cell.set(read value) }
fn main() {
    let first = 1
    let cell = core.cell.Cell.new(read first)
    { let short = 42; set(cell,read short) }
    *cell.get()
}
