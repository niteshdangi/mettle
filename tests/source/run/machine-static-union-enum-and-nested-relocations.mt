
@layout(C)
union Bits { integer: u64; real: f64 }
@layout(C,u8)
copy enum Number { Empty = 7; Integer(u64) = 9 }
@layout(transparent)
copy enum Wrapper { Value(i64,Unit) }
copy type Nested { first: Number; second: Wrapper }
static BITS: Bits = Bits(integer: 0x3ff0000000000000u64)
static VALUE: Number = Number.Integer(42u64)
static NESTED: Nested = Nested(Number.Empty,Wrapper.Value(42i64,()))
static VALUES: [i32;2] = [20,22];
static ADDRESS: ptr<read i32> = core.ptr.from_ref(VALUES[1])
fn main() {
    let value = match VALUE { Number.Integer(value) => value, _ => 0u64 }
    let nested = match NESTED.second { Wrapper.Value(value,_) => value }
    if value == 42u64 && nested == 42i64 && unsafe { BITS.real == 1.0f64 && *ADDRESS == 22 } { 0 } else { 1 }
}
