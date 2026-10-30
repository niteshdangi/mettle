
fn total(limit: i32) {
    var sum = 0
    var current = 0
    while current < limit {
        current += 1
        if current == 2 {
            continue
        }
        sum += current
        if current == 6 {
            break
        }
    }
    sum
}
fn main(): i32 {
    let result: i32
    if total(10) == 19 {
        result = 0
    } else {
        result = 1
    }
    result
}
