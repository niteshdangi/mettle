
fn value<const N:u32=4294967295>():u32 { N }
fn increment<const N:u32>():u32 { value::<{N+1}>() }
fn classify(input:u32):i32 {
    match input { 0..=4294967295 => 42 }
}
fn main() {
    let maximum:u32 = 4294967295
    let minimum:u32 = 0
    var count = 0
    for element in 4294967294u32..=maximum { count += 1 }
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
    let converted = match maximum.checked_cast::<u32>() {
        none => false, present(item) => item == maximum
    }
    if value() == maximum && increment::<{4294967294}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted { 0 } else { 1 }
}
