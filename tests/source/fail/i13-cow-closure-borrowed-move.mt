// expect-error: ownership 9:13 cannot move out of a borrowed place
import alloc.borrow.Cow

type Value { number: i32 }
fn consume(take value: Value): i32 { value.number }

fn bad<region r>(read values: [Value] from r): i32 {
    let cow: Cow<region r, Value> = Cow.Borrowed(read values)
    consume(cow.as_ref()[0usize])
}

fn main(): i32 { 0 }
