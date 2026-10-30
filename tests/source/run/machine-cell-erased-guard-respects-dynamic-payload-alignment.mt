
interface Readable { fn value(): i32; }
@align(64)
type Number { number: i32 }
extend Number implements Readable { fn value(): i32 { self.number } }
fn main() {
    let cell = core.cell.RefCell.new(Number(42))
    let erased: read core.cell.RefCell<any Readable> = read cell
    { let guard = erased.borrow(); if guard.get_ref().value() != 42 { return 1 } }
    let guard = erased.borrow_mut()
    if guard.get_ref().value() == 42 { 0 } else { 2 }
}
