// expect-exit: 0
// profiles: debug release
// Behavioral evidence for the blanket and auto-property trait rows on four
// types: borrow() views the same value, From<T>/Into<A> return the value,
// to_owned() equals a clone, and to_string() renders the Display text.
// f-strings are only accepted by format parameters, so the to_string()
// expectations are the literal Display text instead of f"{v}".

import core.borrow.Borrow
import core.borrow.ToOwned
import core.convert.From
import core.convert.Into
import core.clone.Clone
import alloc.string.ToString
import alloc.string.String
import alloc.boxed.Heap

fn main(): i32 {
    // i32 (primitive::integer)
    let number: i32 = 41
    if *number.clone().borrow() != 41 { return 1 }
    if i32.(From<i32>).`from`(number.clone()) != 41 { return 2 }
    let number_into: i32 = i32.(Into<i32>).into(number.clone())
    if number_into != 41 { return 3 }
    if number.clone().to_owned() != number.clone() { return 4 }
    if number.clone().to_string().as_text() != "41" { return 5 }

    // alloc.string.String (owned String)
    let owned_text = String("blanket")
    if String.(Borrow<String>).borrow(owned_text.clone()).as_text() != "blanket" { return 6 }
    let text_from = String.(From<String>).`from`(owned_text.clone())
    if text_from.as_text() != "blanket" { return 7 }
    let text_into: String = String.(Into<String>).into(owned_text.clone())
    if text_into.as_text() != "blanket" { return 8 }
    if owned_text.clone().to_owned().as_text() != owned_text.clone().as_text() { return 9 }
    if owned_text.clone().to_string().as_text() != "blanket" { return 10 }

    // alloc.boxed.Heap<i32>
    if *Heap<i32>.(Borrow<Heap<i32>>).borrow(Heap<i32>.(From<i32>).`from`(7)).get() != 7 { return 11 }
    if *Heap<i32>.(From<i32>).`from`(7).get() != 7 { return 12 }
    let boxed_into: Heap<i32> = i32.(Into<Heap<i32>>).into(7)
    if *boxed_into.get() != 7 { return 13 }
    let boxed = Heap<i32>.(From<i32>).`from`(7)
    if *boxed.clone().to_owned().get() != *boxed.clone().get() { return 14 }
    if boxed.clone().to_string().as_text() != "7" { return 15 }

    // core.num.Wrapping<i32>
    let wrapped = core.num.Wrapping(9i32)
    if wrapped.clone().borrow().value != 9 { return 16 }
    if wrapped.clone().to_owned().value != wrapped.clone().value { return 17 }
    if wrapped.clone().to_string().as_text() != "9" { return 18 }
    0
}
