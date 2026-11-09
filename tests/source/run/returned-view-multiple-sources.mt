
fn choose(read first: i32, read second: i32, flag: bool): read i32 from (first, second) {
    if flag { read first } else { read second }
}
fn main() {
    let first = 40
    let second = 42
    if *choose(first, second, false) == 42 && *choose(first, second, true) == 40 { 0 } else { 1 }
}
