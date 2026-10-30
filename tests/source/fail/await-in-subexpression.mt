// expect-error: feature 6:17 `await` is supported as a whole statement
async fn g(): i32 { 1 }

async fn f(): i32 {
    let x = 1
    let y = 1 + await g()
    y
}

fn main(): i32 { 0 }
