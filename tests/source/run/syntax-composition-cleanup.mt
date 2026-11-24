type Guard<region r> {
    count: mut i32 from r
    tag: i32
    drop { *self.count += 1 }
}

fn fail(): bool throws i32 { throw 7 }
fn guarded(mut count: i32): Unit throws i32 {
    if let present(guard) = present(Guard(mut count, 1)), try fail() {
        let _ = guard.tag
    }
}

fn choose<region r>(take guard: Guard<region r>, passes: bool): Guard<region r> throws i32 {
    if !passes { throw guard.tag }
    guard
}

fn forward<region r>(take guard: Guard<region r>, passes: bool): Guard<region r> throws i32 {
    try choose(guard, passes)
}

fn main(): i32 {
    var drops = 0
    var observed = 0
    if let present(guard) = present(Guard(mut drops, 1)), false {
        return 1
    } else { observed = drops }
    if observed != 1 { return 2 }

    if let present(guard) = present(Guard(mut drops, 4)), guard.tag == 4 {
        observed = guard.tag
    }
    if observed != 4 || drops != 2 { return 3 }

    var cursor = 0
    while let present(guard) = present(Guard(mut drops, cursor)), guard.tag < 2 {
        cursor += 1
        if cursor == 1 { continue }
    }
    if cursor != 2 || drops != 5 { return 4 }
    while let present(guard) = present(Guard(mut drops, 7)), true {
        if guard.tag == 7 { break }
    }
    if drops != 6 { return 5 }

    let outcome: Outcome<Unit, i32> = capture guarded(drops)
    match take outcome {
        failure(error) => { if error != 7 { return 6 } },
        success(_) => { return 7 }
    }
    if drops != 7 { return 8 }
    match take capture forward(Guard(mut drops, 9), true) {
        success(guard) => { if guard.tag != 9 { return 9 } },
        failure(_) => { return 10 }
    }
    if drops != 8 { return 11 }
    match take capture forward(Guard(mut drops, 12), false) {
        success(_) => { return 12 },
        failure(tag) => { if tag != 12 { return 13 } }
    }
    if drops != 9 { return 14 }
    0
}
