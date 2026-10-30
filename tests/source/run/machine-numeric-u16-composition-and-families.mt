
fn value<const N:u16=65535>():u16 { N }
fn increment<const N:u16>():u16 { value<{N+1}>() }
fn classify(input:u16):i32 {
    match input { 0..=65535 => 42 }
}
fn main() {
    let maximum:u16 = 65535
    let minimum:u16 = 0
    var count = 0
    for element in 65534u16..=maximum { count += 1 }
    let overflow = maximum.overflowing_add(1)
    let checked = match maximum.checked_add(1) {
        none => true, present(item) => false
    }
    let divide = match maximum.checked_div(0) {
        none => true, present(item) => false
    }
    let shift = match maximum.checked_shl(16u32) {
        none => true, present(item) => false
    }
    let converted = match maximum.checked_cast<u16>() {
        none => false, present(item) => item == maximum
    }
    if value() == maximum && increment<{65534}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted { 0 } else { 1 }
}
