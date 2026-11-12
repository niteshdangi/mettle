// profiles: debug release
fn preserve<T: Copy>(read value: T): T { value }

fn main(): i32 {
    let number = 42
    let view = read number
    let direct = preserve<read i32>(view)
    let borrowed = preserve<read i32>(read view)
    let inferred = preserve(view)
    if *direct == 42 && *borrowed == 42 && inferred == 42 { 0 } else { 1 }
}
