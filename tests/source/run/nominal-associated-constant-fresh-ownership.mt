static mut DROPS: i32 = 0
type Owned<T> {
    pub value: i32
    drop { unsafe { DROPS += self.value } }
}
extend<T> Owned<T> { const VALUE: Owned<T> = Owned<T>(7) }
fn consume<T>(take value: Owned<T>): i32 { value.value }
fn main(): i32 {
    var first = Owned<i32>.VALUE
    let second = Owned<i32>.VALUE
    first.value = 11
    if second.value != 7 { return 1 }
    if consume(first) != 11 { return 2 }
    if consume(second) != 7 { return 3 }
    if unsafe { DROPS != 18 } { return 4 }
    { let discarded = Owned<u8>.VALUE }
    if unsafe { DROPS == 25 } { 0 } else { 5 }
}
