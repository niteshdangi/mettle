// expect-error: ownership 9:13 cannot move out of a viewed place
import alloc.borrow.BorrowedOrOwned

type Value { number: i32 }
fn consume(take value: Value): i32 { value.number }

fn bad<region r>(read values: [Value] from r): i32 {
    let cow: BorrowedOrOwned<region r, [Value]> = BorrowedOrOwned.Borrowed(read values)
    consume(cow.as_ref()[0usize])
}

fn main(): i32 { 0 }
