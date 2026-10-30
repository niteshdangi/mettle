// expect-exit: trap
fn main(): i32 { let cell=core.cell.RefCell.new(42); let guard=cell.borrow_mut(); core.mem.forget(guard); let next=cell.borrow(); 0 }
