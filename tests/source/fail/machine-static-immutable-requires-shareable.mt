// expect-error: type 2:1 requires a Shareable type
static CELL: core::cell::Cell<i32> = core::cell::Cell::new(0); fn main() { 0 }
