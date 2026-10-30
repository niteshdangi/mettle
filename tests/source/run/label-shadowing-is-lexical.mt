
fn main() {
    let first = label target: loop {
        let inner = label target: loop { break label target 20 }
        break label target inner + 22
    }
    if first == 42 { 0 } else { 1 }
}
