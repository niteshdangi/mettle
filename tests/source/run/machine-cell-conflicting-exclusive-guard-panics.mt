// expect-exit: trap
fn main(): i32 { let cell=core.cell.RefCell.new(42); let first=cell.borrow(); let second=cell.borrow_mut(); 0 }
