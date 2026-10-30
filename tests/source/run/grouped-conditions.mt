
fn stop() {
    let _ = (false) && { return 7 }
    loop {}
}
fn choose() {
    if ((false)) { return false }
    while (false) { return () }
    if (true) { 42 } else { stop() }
}
fn main() { if choose() == 42 { 0 } else { 1 } }
