
fn main() {
    let answer: i32
    label outer: loop {
        loop { answer = 42; break label outer }
    }
    if answer == 42 { 0 } else { 1 }
}
