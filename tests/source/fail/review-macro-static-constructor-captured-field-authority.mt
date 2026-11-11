// expect-error: name 6:41 private or restricted field 'value' is inaccessible
module owner {
    pub copy type Slot { value: i32 }
    pub macro build { ($field:ident) => { Slot($field: 0) }; }
}
static VALUE: owner.Slot = owner.build!(value)
fn main(): i32 { 0 }
