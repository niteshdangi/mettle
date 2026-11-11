// expect-error: name 7:18 private or restricted field 'value' is inaccessible
module owner {
    pub union Slot { pub unused: i32; value: i32 }
    pub macro build { ($field:ident, $v:expr) => { Slot($field: $v) }; }
}
fn main(): i32 {
    owner.build!(value, 0)
    0
}
