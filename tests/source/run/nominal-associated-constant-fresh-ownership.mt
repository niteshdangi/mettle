static mut DROPS: i32 = 0
type Owned {
    pub value: i32
    drop { unsafe { DROPS += self.value } }
}
extend Owned { const VALUE: Owned = Owned(7) }
fn consume(take value: Owned): i32 { value.value }
fn main(): i32 {
    var first = Owned.VALUE
    let second = Owned.VALUE
    first.value = 11
    if second.value != 7 { return 1 }
    if consume(first) != 11 { return 2 }
    if consume(second) != 7 { return 3 }
    if unsafe { DROPS != 18 } { return 4 }
    { let discarded = Owned.VALUE }
    if unsafe { DROPS == 25 } { 0 } else { 5 }
}
