// expect-error: feature 7:25 `return`, `throw` and `?` are not supported inside a loop
async fn g(): i32 { 1 }

async fn f(): i32 {
    var total = 0
    while total < 3 {
        if total == 2 { return 0 }
        total = total + await g()
    }
    total
}

fn main(): i32 { 0 }
