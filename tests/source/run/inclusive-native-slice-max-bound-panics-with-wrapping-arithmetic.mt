// expect-exit: trap
// flags: --overflow-checks off
fn main(): i32 {
    let values = [1]
    let last = 18_446_744_073_709_551_615usize
    let selected: read [i32] = read values[..=last]
    if selected.len() == 0usize { 0 } else { 1 }
}
