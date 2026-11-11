// expect-error: parse 5:27 `await` is only valid inside an async function body
macro identity { ($value:expr) => { $value }; }
async fn later(): i32 { 1 }
fn main(): i32 {
    let value = identity!(await later())
    value
}
