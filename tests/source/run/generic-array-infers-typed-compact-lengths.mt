fn length<const N: usize>(read values: [i32; N]): usize { N }
fn narrow<const N: u8>(read values: [i32; N]): u8 { N }

fn main(): i32 {
    let expanded = [0; 64]
    let compact = [0; 65]
    let maximum = [0; 255]
    if length(expanded) != 64usize || length(compact) != 65usize ||
       length(maximum) != 255usize || narrow(compact) != 65u8 ||
       narrow(maximum) != 255u8 { return 1 }
    0
}
