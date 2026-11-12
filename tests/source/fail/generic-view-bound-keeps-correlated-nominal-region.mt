// expect-error: region 13:8 interface bound does not hold after region inference
interface Compare<R: unsized> { fn same(read other: R): bool; }
type Holder<region r> { value: read i32 from r }

extend<region r> read i32 from r implements Compare<Holder<region r>> {
    fn same(read other: Holder<region r>): bool { *self == *other.value }
}

fn require_static<L: Compare<Holder<region static>>>(read left: L): bool { true }

fn main(): i32 {
    let number = 42
    if require_static<read i32>(read number) { 0 } else { 1 }
}
