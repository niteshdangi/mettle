
fn choose(first: read i32, second: read i32, flag: bool): read i32 from (first, second) {
    if flag { read first } else { read second }
}
fn main() {
    let first = 40
    let second = 42
    if *choose(first, second, false) == 42 && *choose(first, second, true) == 40 { 0 } else { 1 }
}
