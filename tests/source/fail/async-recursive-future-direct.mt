// expect-error: type 3:11 recursive async future cycle
async fn recursive(): i32 {
    await recursive()
}
fn main(): i32 { 0 }
