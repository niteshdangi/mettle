// profiles: debug release

type Holder<T> { value: T? }

extend<T> Holder<T> {
    static const fn empty(): Holder<T> {
        let value: T? = none
        Holder(value)
    }

    take const fn into_inner(): T? { take self.value }
}

const EMPTY: i32 = match take Holder<i32>.empty().into_inner() {
    present(value) => value,
    none => 42
}

fn main(): i32 {
    if EMPTY == 42 { 0 } else { 1 }
}
