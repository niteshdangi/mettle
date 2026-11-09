// expect-error: type 25:1 overlapping implementations cannot be selected by order

interface From<T> { static fn from(value: take T): Self; }
interface Into<T> { take fn into(): T; }
interface TryFrom<T> {
    type Error;
    static fn try_from(value: take T): Self throws Self.Error;
}

type Input {}
type Output {}

extend Output implements From<Input> {
    static fn from(value: take Input): Output { Output() }
}

extend Output implements TryFrom<Input> {
    type Error = bool
    static fn try_from(value: take Input): Output throws bool { failure(true) }
}

extend<T, U> T implements Into<U> where U: From<T> {
    take fn into(): U { U.(From<T>).from(self) }
}
extend<T, U: Into<T>> T implements TryFrom<U> {
    type Error = Never
    static fn try_from(value: take U): T throws Never {
        success(U.(Into<T>).into(value))
    }
}

fn main(): i32 { 0 }
