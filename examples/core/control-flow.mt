fn sum_to(limit: i32): i32 {
    var total = 0
    var current = 1
    while current <= limit {
        total += current
        current += 1
    }
    total
}

fn main(): i32 {
    let result: i32
    if sum_to(5) == 15 {
        result = 0
    } else {
        result = 1
    }
    result
}
