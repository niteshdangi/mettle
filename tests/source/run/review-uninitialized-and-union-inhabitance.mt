union Choice { impossible: Never; value: i32 }
fn from_storage(read storage: core.mem.MaybeUninit<Never>): i32 { 21 }
fn from_union(read choice: Choice): i32 { unsafe { choice.value } }
fn main(): i32 {
    let storage = core.mem.MaybeUninit<Never>.uninit()
    let choice = Choice(value: 21)
    from_storage(read storage) + from_union(read choice) - 42
}
