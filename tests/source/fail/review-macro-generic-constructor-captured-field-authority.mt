// expect-error: name 7:18 private or restricted field 'value' is inaccessible
module owner {
    pub type Slot<T> { value: T }
    pub macro build { ($field:ident, $v:expr) => { Slot<i32>($field: $v) }; }
}
fn main(): i32 {
    owner.build!(value, 0)
    0
}
