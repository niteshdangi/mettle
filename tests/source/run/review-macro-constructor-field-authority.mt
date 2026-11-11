module owner {
    pub copy type Slot { value: i32 }
    pub copy type Generic<T: Copy> { value: T }
    pub union Bits { pub unused: i32; value: i32 }
    pub macro build { ($t:ty, $v:expr) => { $t(value: $v) }; }
    static POSITION: Slot = builder.positional!(Slot)
    pub fn get(value: Slot): i32 { value.value }
    pub fn get_generic(value: Generic<i32>): i32 { value.value }
    pub fn get_bits(): i32 { unsafe { super.BITS.value } }
    pub fn positional(): i32 {
        let value = builder.positional!(Slot)
        value.value + POSITION.value
    }
}
module builder {
    pub macro positional { ($t:ty) => { $t(7) }; }
}
static SLOT: owner.Slot = owner.build!(owner.Slot, 11)
static BITS: owner.Bits = owner.build!(owner.Bits, 13)
fn main(): i32 {
    let ordinary = owner.build!(owner.Slot, 5)
    let generic = owner.build!(owner.Generic<i32>, 6)
    owner.get(SLOT) + owner.get(ordinary) + owner.get_generic(generic) +
        owner.get_bits() + owner.positional() - 49
}
