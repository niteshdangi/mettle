fn stop(): Never {
    loop {
    }
}

fn inferred_stop() {
    loop {
    }
}

fn choose(flag: bool) {
    if flag {
        42
    } else {
        inferred_stop()
    }
}

fn discard_result() {
    let _ = choose(true)
}

fn main(): i32 {
    let completed: Unit = discard_result()
    let _ = completed
    if choose(true) == 42 {
        0
    } else {
        1
    }
}
