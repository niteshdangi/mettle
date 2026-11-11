import alloc.borrow.BorrowedOrOwned
import alloc.string.String
import core.clone.Clone
import core.text.Text

fn text<region r>(read source: Text from r): i32 {
    var cow: BorrowedOrOwned<region r, Text> =
        BorrowedOrOwned.Borrowed(read source)
    let borrowed_clone = cow.clone()
    if cow.is_owned() || !borrowed_clone.is_borrowed() { return 1 }
    cow.to_mut().push_str("!")
    if !cow.is_owned() || cow.as_ref() != "hello!" ||
        borrowed_clone.as_ref() != "hello" || (read source) != "hello" {
        return 2
    }
    let owned_clone = cow.clone()
    cow.to_mut().push_str("?")
    if owned_clone.as_ref() != "hello!" || cow.as_ref() != "hello!?" {
        return 3
    }
    let address = cow.to_mut().as_ptr()
    let moved: String = cow.into_owned()
    if moved.as_ptr() != address || moved.as_text() != "hello!?" { return 4 }
    let borrowed_owner: String = borrowed_clone.into_owned()
    if borrowed_owner.as_text() != "hello" { return 5 }
    0
}

fn main(): i32 { text("hello") }
