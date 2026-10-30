
type Counted { counter: ptr<mut i32>; drop { unsafe { *self.counter += 1 } } }
fn main() {
    var count = 0
    let counter = core::ptr::from_mut(count)
    {
        let cell = core::cell::RefCell::new(Counted(counter))
        { let first = cell.borrow(); let second = cell.borrow() }
        { let exclusive = cell.borrow_mut() }
        if count != 0 { return 1 }
    }
    if count == 1 { 0 } else { 2 }
}
