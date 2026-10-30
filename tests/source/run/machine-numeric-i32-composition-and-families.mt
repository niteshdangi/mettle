
fn value<const N:i32=2147483647>():i32 { N }
fn increment<const N:i32>():i32 { value<{N+1}>() }
fn classify(input:i32):i32 {
    match input { -2147483648..=2147483647 => 42 }
}
fn main() {
    let maximum:i32 = 2147483647
    let minimum:i32 = -2147483648
    var count = 0
    for element in 2147483646i32..=maximum { count += 1 }
    let overflow = maximum.overflowing_add(1)
    let checked = match maximum.checked_add(1) {
        none => true, present(item) => false
    }
    let divide = match maximum.checked_div(0) {
        none => true, present(item) => false
    }
    let shift = match maximum.checked_shl(32u32) {
        none => true, present(item) => false
    }
    let converted = match maximum.checked_cast<i32>() {
        none => false, present(item) => item == maximum
    }
    if value() == maximum && increment<{2147483646}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted { 0 } else { 1 }
}
