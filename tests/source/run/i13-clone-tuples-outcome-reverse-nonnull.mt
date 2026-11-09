// profiles: debug release
// Clone for tuples of every arity up to twelve (field by field), the stored
// outcome (success and failure), Reverse and NonNull; the ToOwned blanket then
// applies to each.
import core.clone.Clone
import core.borrow.ToOwned
import core.cmp
import core.cmp.{PartialEq, Reverse}
import core.ptr.NonNull
import core.outcome

type Counted { value: i32 }
extend Counted implements Clone {
    fn clone(): Counted { Counted(self.value + 1) }
}

fn owned_ok<T: ToOwned>() {}

fn main(): i32 {
    let one = (Counted(1),)
    if one.clone().0.value != 2 { return 1 }
    let pair = (Counted(1), 7i32)
    let copied = pair.clone()
    if copied.0.value != 2 || copied.1 != 7 { return 2 }
    let wide = (1i8, 2i16, 3i32, 4i64, 5u8, 6u16, 7u32, 8u64, true, 'x', 9i128, Counted(10))
    let wider = wide.clone()
    if wider.0 != 1i8 || wider.8 != true || wider.9 != 'x' || wider.11.value != 11 { return 3 }
    let good: (Outcome<Counted, Counted>) = success(Counted(4))
    match good.clone() { success(c) => if c.value != 5 { return 4 }, failure(_) => { return 5 } }
    let bad: (Outcome<Counted, Counted>) = failure(Counted(8))
    match bad.clone() { success(_) => { return 6 }, failure(c) => if c.value != 9 { return 7 } }
    let reversed = Reverse(Counted(20))
    if reversed.clone().value.value != 21 { return 8 }
    var target = 5
    match NonNull.new(core.ptr.from_mut(target)) {
        present(pointer) => if pointer.clone().as_ptr() != pointer.as_ptr() { return 9 },
        none => { return 10 }
    }
    owned_ok<(i32, bool, char)>()
    owned_ok<(Outcome<i32, bool>)>()
    owned_ok<Reverse<i32>>()
    owned_ok<NonNull<i32>>()
    0
}
