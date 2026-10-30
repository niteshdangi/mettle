
fn value<const N:i128=170141183460469231731687303715884105727>():i128 { N }
fn increment<const N:i128>():i128 { value::<{N+1}>() }
fn classify(input:i128):i32 {
    match input { -170141183460469231731687303715884105728..=170141183460469231731687303715884105727 => 42 }
}
fn main() {
    let maximum:i128 = 170141183460469231731687303715884105727
    let minimum:i128 = -170141183460469231731687303715884105728
    var count = 0
    for element in 170141183460469231731687303715884105726i128..=maximum { count += 1 }
    let overflow = maximum.overflowing_add(1)
    let checked = match maximum.checked_add(1) {
        none => true, present(item) => false
    }
    let divide = match maximum.checked_div(0) {
        none => true, present(item) => false
    }
    let shift = match maximum.checked_shl(128u32) {
        none => true, present(item) => false
    }
    let converted = match maximum.checked_cast::<i128>() {
        none => false, present(item) => item == maximum
    }
    if value() == maximum && increment::<{170141183460469231731687303715884105726}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted { 0 } else { 1 }
}
