
interface Code { fn code():i32; }
type Key<const N:u128> {}
extend Key<0> implements Code { fn code():i32 { 1 } }
extend Key<18446744073709551616> implements Code { fn code():i32 { 42 } }
fn inspect<T:Code>(value:read T):i32 { value.code() }
fn main() {
    let first=Key<0>()
    let second=Key<18446744073709551616>()
    if inspect(first)==1 && inspect(second)==42 { 0 } else { 1 }
}
