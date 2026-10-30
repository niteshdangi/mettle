
fn value<const N:u64=18446744073709551615>():u64 { N }
fn increment<const N:u64>():u64 { value::<{N+1}>() }
fn classify(input:u64):i32 {
    match input { 0..=18446744073709551615 => 42 }
}
fn main() {
    let maximum:u64 = 18446744073709551615
    let minimum:u64 = 0
    var count = 0
    for element in 18446744073709551614u64..=maximum { count += 1 }
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
    let converted = match maximum.checked_cast::<u64>() {
        none => false, present(item) => item == maximum
    }
    if value() == maximum && increment::<{18446744073709551614}>() == maximum &&
       classify(minimum) == 42 && classify(maximum) == 42 && count == 2 &&
       overflow.0 == minimum && overflow.1 &&
       maximum.wrapping_add(1) == minimum &&
       maximum.saturating_add(1) == maximum &&
       minimum.wrapping_neg() == minimum &&
       checked && divide && shift && converted { 0 } else { 1 }
}
