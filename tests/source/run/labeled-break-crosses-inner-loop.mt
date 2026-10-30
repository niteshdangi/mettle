
fn answer() {
    label outer: loop {
        loop { break label outer 42 }
    }
}
fn main() { if answer() == 42 { 0 } else { 1 } }
