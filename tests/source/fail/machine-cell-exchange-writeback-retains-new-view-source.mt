// expect-error: ownership 8:44 access or storage lifetime conflicts with a live read loan

fn set<region a>(cell: read core::cell::Cell<read i32 from a>,
                 value: read i32 from a) { cell.set(read value) }
fn main() {
    let first = 1
    let cell = core::cell::Cell::new(read first)
    { let short = 42; set(cell,read short) }
    *cell.get()
}
