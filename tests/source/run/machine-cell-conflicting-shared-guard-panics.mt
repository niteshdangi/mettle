// expect-exit: trap
fn main(): i32 { let cell=core::cell::RefCell::new(42); let first=cell.borrow_mut(); let second=cell.borrow(); 0 }
