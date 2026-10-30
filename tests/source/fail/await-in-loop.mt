// expect-error: feature 7:25 `await` inside a loop is not implemented
async fn g(): i32 { 1 }

async fn f(): i32 {
    var total = 0
    while total < 3 {
        total = total + await g()
    }
    total
}

fn main(): i32 { 0 }
