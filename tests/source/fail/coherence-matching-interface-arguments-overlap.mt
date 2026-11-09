// expect-error: type 19:1 overlapping implementations cannot be selected by order

interface Source<T> {
    static fn make(): T;
}
interface Output<T> {
    static fn make(): T;
}
type Number {}

extend Number implements Source<bool> {
    static fn make(): bool { true }
}
extend<T, U: Source<T>> U implements Output<T> {
    static fn make(): T { U.(Source<T>).make() }
}

// Both implementations apply to Output<bool> for Number.
extend Number implements Output<bool> {
    static fn make(): bool { false }
}

fn main(): i32 { 0 }
