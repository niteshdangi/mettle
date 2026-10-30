
fn main() {
    var x = 1
    x += { x = 5; 1 }
    if x == 6 { 0 } else { 1 }
}
