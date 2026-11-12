// profiles: debug release
interface Compare<R: unsized> { fn same(read other: R): bool; }
type Holder<region r> { value: read i32 from r }

extend<region r, region s> read i32 from r implements Compare<Holder<region s>> {
    fn same(read other: Holder<region s>): bool { *self == *other.value }
}

extend<region s> i32 implements Compare<Holder<region s>> {
    fn same(read other: Holder<region s>): bool { self == *other.value }
}

fn compare<L: Compare<R> + unsized, R: unsized>(read left: L, read right: R): bool {
    L.(Compare<R>).same(left, right)
}

static ROOT: i32 = 42

fn main(): i32 {
    let number = 42
    let holder: Holder<region static> = Holder(read ROOT)
    let fixed = compare<read i32 from static, Holder<region static>>(read ROOT, holder)
    let plain = compare<i32, Holder<region static>>(number, holder)
    if fixed && plain && compare<read i32, Holder<region static>>(read number, holder) { 0 } else { 1 }
}
