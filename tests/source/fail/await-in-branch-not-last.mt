// expect-error: feature 7:13 `await` in a branch that is not last in its block cannot also contain `return`
async fn g(): i32 { 1 }

async fn f(c: bool): i32 {
    var n = 0
    if c {
        n = await g()
        return n
    }
    n + 1
}

fn main(): i32 { 0 }
