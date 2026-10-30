
fn identity(value:i32):i32 { value }
fn main():i32 {
    identity(match 1 {
        1 => 0
        _ => 3
    })
}
