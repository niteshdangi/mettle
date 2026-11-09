// expect-exit: 0
// profiles: debug release

interface Source<T> {
    static fn make(): T;
}
interface Output<T> {
    static fn make(): T;
}
type Number {}

extend Number implements Source<i32> {
    static fn make(): i32 { 42 }
}
extend<T, U: Source<T>> U implements Output<T> {
    static fn make(): T { U.(Source<T>).make() }
}
extend Number implements Output<bool> {
    static fn make(): bool { true }
}

fn main(): i32 {
    if Number.(Output<i32>).make() != 42 { return 1 }
    if !Number.(Output<bool>).make() { return 2 }
    0
}
