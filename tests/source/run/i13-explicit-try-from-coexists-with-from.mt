// profiles: debug release
import core.convert.{From, Into, TryFrom, TryInto}

type Value { value: i32 }
enum ConversionError { Negative }

extend Value implements From<i32> {
    static fn from(take value: i32): Value { Value(value) }
}

extend Value implements TryFrom<i32> {
    type Error = ConversionError
    static fn try_from(take value: i32): (Outcome<Value, ConversionError>) {
        if value < 0 { failure(ConversionError.Negative) }
        else { success(Value(value)) }
    }
}

fn main(): i32 {
    let direct = Value.(From<i32>).from(-1)
    if direct.value != -1 { return 1 }
    let forwarded: Value = i32.(Into<Value>).into(-2i32)
    if forwarded.value != -2 { return 2 }
    match Value.(TryFrom<i32>).try_from(3) {
        success(value) => { if value.value != 3 { return 3 } },
        failure(_) => { return 3 }
    }
    match i32.(TryInto<Value>).try_into(-4i32) {
        success(_) => { return 4 },
        failure(error) => match error {
            ConversionError.Negative => {}
        }
    }
    0
}
