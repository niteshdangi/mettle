// expect-error: feature 6:18 `await` is not allowed in a lazily evaluated operand
async fn g(): bool { true }

async fn f(): bool {
    let x = true
    let y = x && await g()
    y
}

fn main(): i32 { 0 }
