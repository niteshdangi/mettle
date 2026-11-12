// profiles: debug release

interface Factory: Sized { static fn create(): Self; }
type Holder<T> { value: T }

extend Holder<[i32; 3]> implements Factory {
    static fn create(): Holder<[i32; 3]> { Holder([4i32; 3]) }
}

fn main(): i32 {
    let value = Holder<[i32; 3]>.create()
    if value.value[1] == 4 { 0 } else { 1 }
}
