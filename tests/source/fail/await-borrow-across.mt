// expect-error: feature 6:5 `view` is a borrow that is still used after an `await`
async fn g(): i32 { 1 }

async fn f(): i32 {
    let value = 1
    let view = read value
    let n = await g()
    view + n
}

fn main(): i32 { 0 }
