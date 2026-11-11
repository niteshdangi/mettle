type Guard {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}

fn guarded_source(take _guard: Guard, mut calls: i32,
                  values: [i32;2]): [i32;2] {
    calls += 1
    values
}

fn conditional_break(stop: bool, mut evaluations: i32,
                     mut drops: i32, mut total: i32): Unit {
    for item in {
        let _guard = Guard(core.ptr.from_mut(drops))
        evaluations += 1
        if stop { break }
        [7]
    } {
        total += item
    }
}

fn return_from_source(mut evaluations: i32, mut drops: i32): i32 {
    for _ in {
        let _guard = Guard(core.ptr.from_mut(drops))
        evaluations += 1
        return 9;
        [0]
    } {
        let checked: i32 = 1
        evaluations += checked
    }
    0
}

fn main(): i32 {
    var evaluations = 0
    var drops = 0
    var total = 0
    for _ in {
        let _guard = Guard(core.ptr.from_mut(drops))
        evaluations += 1
        break;
        [0]
    } {
        let checked: i32 = 100
        total += checked
    }
    if evaluations != 1 || drops != 1 || total != 0 { return 1 }
    conditional_break(true, evaluations, drops, total)
    if evaluations != 2 || drops != 2 || total != 0 { return 2 }
    conditional_break(false, evaluations, drops, total)
    if evaluations != 3 || drops != 3 || total != 7 { return 3 }

    var attempts = 0
    var iterations = 0
    for item in {
        let _guard = Guard(core.ptr.from_mut(drops))
        evaluations += 1
        attempts += 1
        if attempts < 3 { continue }
        [11,13]
    } {
        total += item
        iterations += 1
    }
    if evaluations != 6 || drops != 6 || total != 31 ||
       attempts != 3 || iterations != 2 { return 4 }
    if return_from_source(evaluations, drops) != 9 { return 5 }
    if evaluations != 7 || drops != 7 { return 6 }
    attempts = 0
    var calls = 0
    for item in guarded_source(Guard(core.ptr.from_mut(drops)), calls, {
        attempts += 1
        if drops != 6 + attempts { return 7 }
        if attempts < 3 { continue }
        [17,19]
    }) {
        total += item
    }
    if attempts == 3 && calls == 1 && drops == 10 && total == 67 {
        0
    } else { 8 }
}
