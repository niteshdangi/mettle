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

const fn relay<T>(take value: T): T {
    let moved = value
    moved
}

const REUSED: i32 = {
    let scalar = relay<i32>(17)
    let enabled = relay<bool>(true)
    let owned = relay<Holder<i32>>(Holder<i32>(present(25)))
    if enabled {
        scalar + match take owned.into_inner() {
            present(value) => value,
            none => 0
        }
    } else { 0 }
}

enum Choice<T> { One(T); Pair(T, T); Empty }

const fn score(take choice: Choice<i32>): i32 {
    match choice {
        Choice.One(value) => value,
        Choice.Pair(left, right) => left + right,
        Choice.Empty => 0
    }
}

const SHARED: i32 = (
    score(Choice<i32>.One(7)) + score(Choice<i32>.Pair(11, 13)) +
    score(Choice<i32>.Empty)
)

fn main(): i32 {
    if EMPTY == 42 && REUSED == 42 && SHARED == 31 { 0 } else { 1 }
}
