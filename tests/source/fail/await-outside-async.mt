// expect-error: parse 6:13 `await` is only valid inside an async function body
async fn g(): i32 { 1 }

fn main(): i32 {
    let x = 1
    let y = await g()
    0
}
