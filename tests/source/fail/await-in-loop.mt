// expect-error: feature 6:15 `await` in a loop is supported only when the loop is a statement of its own
async fn g(): i32 { 1 }

async fn f(): i32 {
    let n = loop {
        break await g()
    }
    n
}

fn main(): i32 { 0 }
