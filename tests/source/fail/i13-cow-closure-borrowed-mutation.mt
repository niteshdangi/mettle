// expect-error: ownership 8:5 mutable place
import alloc.borrow.Cow

type Value { number: i32 }

fn bad<region r>(read values: [Value] from r): Unit {
    let cow: Cow<region r, Value> = Cow.Borrowed(read values)
    cow.as_ref()[0usize].number = 99
}

fn main(): i32 { 0 }
