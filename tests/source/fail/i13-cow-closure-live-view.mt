// expect-error: ownership 11:5 access or storage conflicts
import alloc.borrow.BorrowedOrOwned
import alloc.string
import core.text.Text

fn bad<region r>(read source: Text from r): usize {
    var cow: BorrowedOrOwned<region r, Text> =
        BorrowedOrOwned.Borrowed(read source)
    cow.to_mut().push_str("!")
    let view = cow.as_ref()
    cow.to_mut().push_str("?")
    view.len()
}

fn main(): i32 { 0 }
