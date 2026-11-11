// flags: --overflow-checks off
fn main(): i32 {
    let n = core.hint.black_box(251u8)
    if n.next_multiple_of(10u8) != 4u8 { return 1 }
    if 250u8.next_multiple_of(10u8) != 250u8 { return 2 }
    match n.checked_next_multiple_of(10u8) {
        present(_) => { return 3 },
        none => {}
    }
    match n.checked_next_multiple_of(0u8) {
        present(_) => { return 4 },
        none => {}
    }
    0
}
