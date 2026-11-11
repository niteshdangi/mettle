module source_helpers;
import core.future.Future

async fn read_value(read value: i32): i32 { value + 1 }

fn drive<F: Future>(take future: F): F.Output {
    source_helpers.drive!(future)
}

fn main(): i32 {
    let value = 41
    let boxed = alloc.boxed.new(read_value(read value))
    let future = boxed.into_inner()
    if drive(future) == 42 { 0 } else { 1 }
}
