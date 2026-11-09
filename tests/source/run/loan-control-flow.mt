
fn combine(read value: i32, extra: i32) { value + extra }
fn choose(flag: bool) {
    var value = 40
    combine(value, if flag { return 42 } else { 2 })
}
fn unused() {
    var value = 40
    combine(value, { value = 42; return value })
}
fn main() {
    if choose(true) == 42 && choose(false) == 42 && unused() == 42 { 0 } else { 1 }
}
