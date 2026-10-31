import std.thread

fn main(): i32 {
    let owner: shared i32 = shared 41
    let retained = owner.retain()
    let handle = thread.spawn(take fn(): i32 { *retained.get() })
    let outcome = capture handle.join()
    let value = match take outcome {
        success(result) => result,
        failure(_) => { return 1 }
    }
    if value == 41 && owner.strong_count() == 1usize { 0 } else { 2 }
}
