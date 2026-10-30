
fn choose(cell: read core.cell.RefCell<i32>, condition: bool): i32 {
    if condition {
        var guard = cell.borrow_mut()
        *guard.get_mut() += 1
        return *guard.get_ref()
    }
    let guard = cell.borrow()
    *guard.get_ref()
}
fn main() {
    let cell = core.cell.RefCell.new(40)
    let first = choose(cell,true)
    let second = choose(cell,false)
    let outcome = cell.try_borrow_mut()
    let result = match take outcome {
        success(guard) => { var guard = guard; *guard.get_mut() += 1; *guard.get_ref() },
        failure(error) => 0
    }
    if first == 41 && second == 41 && result == 42 { 0 } else { 1 }
}
