
fn value<const N:u8=255>():u8 { N }
fn increment<const N:u8>():u8 { value::<{N+1}>() }
fn classify(input:u8):i32 {
    match input { 0..=255 => 42 }
}
fn main() {
    let maximum:u8 = 255
    let minimum:u8 = 0
    var count = 0
    for element in 254u8..=maximum { count += 1 }
    let overflow = maximum.overflowing_add(1)
    let checked = match maximum.checked_add(1) {
        none => true, present(item) => false
    }
    let divide = match maximum.checked_div(0) {
        none => true, present(item) => false
    }
    let shift = match maximum.checked_shl(8u32) {
        none => true, present(item) => false
    }
    let converted = match maximum.checked_cast::<u8>() {
        none => false, present(item) => item == maximum
    }
    if value() == maximum && increment::<{254}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted { 0 } else { 1 }
}
