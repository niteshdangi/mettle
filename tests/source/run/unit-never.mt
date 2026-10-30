
fn stop(): Never { loop {} }
fn inferred_stop() { loop {} }
fn unit_value(): Unit { () }
fn ignored() { let _ = 42 }
fn choose(flag: bool) {
    if flag { 42 } else { inferred_stop() }
}
fn main() {
    let a: Unit = unit_value()
    let b: Unit = ignored()
    let _ = (a)
    if choose(true) == 42 && a == b { 0 } else { 1 }
}
