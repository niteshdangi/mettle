
fn value<const N:i64=9223372036854775807>():i64 { N }
fn increment<const N:i64>():i64 { value::<{N+1}>() }
fn classify(input:i64):i32 {
    match input { -9223372036854775808..=9223372036854775807 => 42 }
}
fn main() {
    let maximum:i64 = 9223372036854775807
    let minimum:i64 = -9223372036854775808
    var count = 0
    for element in 9223372036854775806i64..=maximum { count += 1 }
    let overflow = maximum.overflowing_add(1)
    let checked = match maximum.checked_add(1) {
        none => true, present(item) => false
    }
    let divide = match maximum.checked_div(0) {
        none => true, present(item) => false
    }
    let shift = match maximum.checked_shl(64u32) {
        none => true, present(item) => false
    }
    let converted = match maximum.checked_cast::<i64>() {
        none => false, present(item) => item == maximum
    }
    if value() == maximum && increment::<{9223372036854775806}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted { 0 } else { 1 }
}
