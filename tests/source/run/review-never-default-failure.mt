fn value(x: i32 = 42): i32 throws Never { x }
fn forward(): i32 throws Never { try value() }
fn main(): i32 {
    match capture forward() { success(result) => result - 42 }
}
