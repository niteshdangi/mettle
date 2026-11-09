// profiles: debug release
// `Owner.member(args)` calls the static method of the one interface Owner
// implements for those arguments, like the qualified `Owner.(I).member(args)`:
// the interface parameter of From/TryFrom comes from the argument's type, and
// a generic owner's explicit arguments instantiate Self.
import core.num
import core.num.TryFromIntError
import core.convert.{From, TryFrom}
import core.default.Default

type Meters { value: i64 }
type Feet { value: i64 }
extend Meters implements From<Feet> {
    static fn from(take feet: Feet): Meters { Meters(feet.value * 3) }
}
type Boxed<T> { item: T }
extend Boxed<i32> implements Default {
    static fn default(): Boxed<i32> { Boxed(9) }
}
extend Meters implements Default {
    static fn default(): Meters { Meters(42) }
}

fn main(): i32 {
    if Meters.from(Feet(2)).value != 6 { return 1 }
    if u64.from(7u32) != 7u64 || i128.from(-5i8) != -5i128 || u16.from(true) != 1u16 { return 2 }
    match i8.try_from(300i32) { success(_) => { return 3 }, failure(_) => {} }
    match u8.try_from(200i64) { success(value) => if value != 200u8 { return 4 }, failure(_) => { return 5 } }
    if Meters.default().value != 42 { return 6 }
    if u32.default() != 0u32 { return 7 }
    if Boxed<i32>.default().item != 9 { return 8 }
    0
}
