static mut DROPS: i32 = 0
type Guard { drop { unsafe { DROPS += 1 } } }
fn main(): i32 {
    unsafe { DROPS = 0 }
    if let none = present(Guard()) {
        return 1
    } else {
        if unsafe { DROPS } != 1 { return 2 }
    }
    if let present(value) = present(Guard()) {
        if unsafe { DROPS } != 1 { return 3 }
    } else {
        return 4
    }
    if unsafe { DROPS } != 2 { return 5 }
    0
}
