const fn checked(value: i32): i32 throws i32 {
    if value < 0 { throw -value }
    value * 2
}

const fn forward(value: i32): i32 throws i32 { try checked(value) + 1 }

const fn through_loop(value: i32): i32 throws i32 {
    loop {
        try checked(value)
        break 19
    }
}

const fn through_for(): i32 throws i32 {
    for value in [1, -7, 3] { try checked(value) }
    0
}

const fn from_outcome(failed: bool): i32 throws i32 {
    let value: Outcome<i32, i32> = if failed { failure(23) } else { success(29) }
    try value
}

const fn nested(): i32 throws i32 {
    match capture checked(-11) {
        success(_) => 0,
        failure(error) => try checked(error)
    }
}

static GOOD: Outcome<i32, i32> = capture forward(3)
static BAD: Outcome<i32, i32> = capture forward(-5)
static LOOP_GOOD: Outcome<i32, i32> = capture through_loop(1)
static LOOP_BAD: Outcome<i32, i32> = capture through_loop(-13)
static FOR_BAD: Outcome<i32, i32> = capture through_for()
static OUTCOME_GOOD: Outcome<i32, i32> = capture from_outcome(false)
static OUTCOME_BAD: Outcome<i32, i32> = capture from_outcome(true)
static NESTED: Outcome<i32, i32> = capture nested()

fn main(): i32 {
    match GOOD { success(value) => { if value != 7 { return 1 } }, failure(_) => { return 2 } }
    match BAD { failure(error) => { if error != 5 { return 3 } }, success(_) => { return 4 } }
    match LOOP_GOOD { success(value) => { if value != 19 { return 5 } }, failure(_) => { return 6 } }
    match LOOP_BAD { failure(error) => { if error != 13 { return 7 } }, success(_) => { return 8 } }
    match FOR_BAD { failure(error) => { if error != 7 { return 9 } }, success(_) => { return 10 } }
    match OUTCOME_GOOD { success(value) => { if value != 29 { return 11 } }, failure(_) => { return 12 } }
    match OUTCOME_BAD { failure(error) => { if error != 23 { return 13 } }, success(_) => { return 14 } }
    match NESTED { success(value) => { if value != 22 { return 15 } }, failure(_) => { return 16 } }
    0
}
