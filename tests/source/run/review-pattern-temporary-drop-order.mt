static mut DROPS: i32 = 0
type Guard { drop { unsafe { DROPS += 1 } } }
fn yes(read guard: Guard): bool { true }
fn no(read guard: Guard): bool { false }
fn main(): i32 {
    unsafe { DROPS = 0 }
    let first = match 1 {
        _ if yes(Guard()) => unsafe { DROPS },
        _ => 99,
    }
    if first != 1 { return 3 }
    let second = match 1 {
        _ if no(Guard()) => 99,
        _ => unsafe { DROPS },
    }
    if second != 2 { return 4 }
    0
}
