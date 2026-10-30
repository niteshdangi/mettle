// expect-error: feature 7:13 `await` in a branch is supported only
async fn g(): i32 { 1 }

async fn f(c: bool): i32 {
    var n = 0
    if c {
        n = await g()
    }
    n
}

fn main(): i32 { 0 }
