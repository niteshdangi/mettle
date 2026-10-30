// expect-error: ownership 4:19 may have been moved

fn twice<F: take fn(): i32>(operation: take F): i32 {
    operation() + operation()
}
fn answer(): i32 { 42 }
fn main(): i32 { twice(answer) }
