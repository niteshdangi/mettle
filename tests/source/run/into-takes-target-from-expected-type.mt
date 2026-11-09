// profiles: debug release
// `value.into()` and `value.try_into()` take their target from the type the
// context expects (a let annotation or a parameter), through the blanket
// Into/TryInto implementations.
import core.num
import core.num.TryFromIntError
import core.convert.{From, Into, TryFrom, TryInto}

type Meters { value: i64 }
type Feet { value: i64 }
extend Meters implements From<Feet> {
    static fn from(take feet: Feet): Meters { Meters(feet.value * 3) }
}

fn length(m: Meters): i64 { m.value }
fn wide(v: u64): u64 { v }

fn main(): i32 {
    let m: Meters = Feet(2).into()
    if m.value != 6 { return 1 }
    if length(Feet(5).into()) != 15 { return 2 }
    let d: u64 = 7u32.into()
    if d != 7u64 || wide(9u16.into()) != 9u64 { return 3 }
    let narrowed: (Outcome<u8, TryFromIntError>) = (-1i32).try_into()
    match narrowed { success(_) => { return 4 }, failure(_) => {} }
    let fits: (Outcome<u8, TryFromIntError>) = 200i32.try_into()
    match fits { success(value) => if value != 200u8 { return 5 }, failure(_) => { return 6 } }
    0
}
