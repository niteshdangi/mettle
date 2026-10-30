// expect-error: ownership 9:5 live read loan

fn main(): i32 {
    let escaped = {
        let value = 42
        let closure = fn(): i32 { value }
        let copied = closure
        copied
    }
    escaped()
}
