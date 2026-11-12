fn singleton<region r>(read x: i32 from r): [read i32 from r; 1] {
    [read x]
}
fn pair<region r>(read x: i32 from r, read y: i32 from r): [read i32 from r; 2] {
    [read x, read y]
}
fn repeated<region r>(read x: i32 from r): [read i32 from r; 2] {
    [read x; 2]
}
fn main(): i32 {
    let value = 42
    let other = 17
    let views = singleton(value)
    let pairs = pair(value, other)
    let copies = repeated(value)
    if *views[0] == 42 && *pairs[0] == 42 && *pairs[1] == 17 &&
       *copies[0] == 42 && *copies[1] == 42 { 0 } else { 1 }
}
