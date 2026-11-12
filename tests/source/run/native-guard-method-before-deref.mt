// profiles: debug release

fn main(): i32 {
    let owner = core.cell.RefCell.new([1i32, 2])
    let slice: read core.cell.RefCell<[i32]> = read owner
    {
        var guard = slice.borrow_mut()
        guard.get_mut()[0] = 42
        if guard.get_ref()[0] != 42 { return 1 }
    }
    let guard = slice.borrow()
    let cloned = guard.clone()
    if cloned.get_ref()[0] == 42 && guard.get_ref()[1] == 2 { 0 } else { 2 }
}
