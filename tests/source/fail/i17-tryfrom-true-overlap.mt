// expect-error: type 9:1 overlapping implementations cannot be selected by order
import core.convert.{From, TryFrom}

type Converted { value: i32 }
extend Converted implements From<i32> {
    static fn from(take value: i32): Converted { Converted(value) }
}

extend Converted implements TryFrom<i32> {
    type Error = Never
    static fn try_from(take value: i32): Outcome<Converted, Never> {
        success(Converted(value))
    }
}
