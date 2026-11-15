import core.convert.TryFrom

type Input { value: i32 }
type Output { value: i32 }

macro concrete_try_from {
    ($target:ident, $source:ident) => {
        extend $target implements TryFrom<$source> {
            type Error = bool
            static fn try_from(take value: $source): (Outcome<$target, bool>) {
                success($target(value.value))
            }
        }
    };
}

concrete_try_from!(Output, Input)

fn main(): i32 {
    match take Output.(TryFrom<Input>).try_from(Input(7)) {
        success(value) => { if value.value != 7 { return 1 } },
        failure(_) => { return 2 }
    }
    match i32.(TryFrom<i32>).try_from(9i32) {
        success(value) => { if value != 9 { return 3 } },
        failure(_) => { return 4 }
    }
    0
}
