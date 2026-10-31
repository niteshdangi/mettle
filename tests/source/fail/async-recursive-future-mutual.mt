// expect-error: type 3:11 recursive async future cycle
async fn first(): i32 {
    await second()
}
async fn second(): i32 {
    await first()
}
fn main(): i32 { 0 }
