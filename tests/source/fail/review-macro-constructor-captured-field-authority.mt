// expect-error: name 7:18 private or restricted field 'value' is inaccessible
module owner {
    pub type Slot { value: i32 }
    pub macro build { ($field:ident, $v:expr) => { Slot($field: $v) }; }
}
fn main(): i32 {
    owner.build!(value, 0)
    0
}
