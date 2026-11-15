// expect-error: type 10:9 overlapping implementations cannot be selected by order

interface TryFrom<T> {}
type Value {}

extend<T> T implements TryFrom<T> {}

macro concrete_try_from {
    ($target:ident) => {
        extend $target implements TryFrom<$target> {}
    };
}
concrete_try_from!(Value)

fn main(): i32 { 0 }
