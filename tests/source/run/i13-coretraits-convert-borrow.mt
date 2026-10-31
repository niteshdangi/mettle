import core.borrow
import core.borrow.AsRef
import core.borrow.Borrow
import core.borrow.ToOwned
import core.convert
import core.convert.From
import core.convert.Into
import core.convert.TryFrom
import core.convert.TryInto

type Wrapped { value: i32 }
enum ConversionError { Negative }

extend Wrapped implements From<i32> {
    static fn from(value: take i32): Wrapped { Wrapped(value) }
}

type Positive { value: i32 }
extend Positive implements TryFrom<i32> {
    type Error = ConversionError
    static fn try_from(value: take i32): (Positive throws ConversionError) {
        if value < 0 { failure(ConversionError.Negative) }
        else { success(Positive(value)) }
    }
}

fn main(): i32 {
    let wrapped = Wrapped.(From<i32>).`from`(17)
    if wrapped.value != 17 { return 1 }
    let via_into: Wrapped = i32.(Into<Wrapped>).into(18i32)
    if via_into.value != 18 { return 2 }
    let via_try_from: (Positive throws ConversionError) =
        Positive.(TryFrom<i32>).try_from(19)
    match via_try_from {
        success(value) => { if value.value != 19 { return 3 } },
        failure(_) => { return 3 }
    }
    let via_try_into: (Positive throws ConversionError) =
        i32.(TryInto<Positive>).try_into(20i32)
    match via_try_into {
        success(value) => { if value.value != 20 { return 4 } },
        failure(_) => { return 4 }
    }

    let owned = 21i32.to_owned()
    if owned != 21 { return 5 }
    var target = 0i32
    21i32.clone_into(mut target)
    if target != 21 { return 6 }
    let borrowed = wrapped.as_ref()
    if borrowed.value != 17 { return 7 }
    let key = wrapped.borrow()
    if key.value != 17 { return 8 }
    0
}
