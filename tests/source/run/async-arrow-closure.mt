module source_helpers;
import core.future.Future

fn drive<F: Future<Output = i32>>(take future: F): i32 {
    source_helpers.drive!(future)
}

fn main(): i32 {
    let captured = 5
    let add = async fn(value: i32): i32 => value + captured
    if drive(add(7)) != 12 { return 1 }
    0
}
