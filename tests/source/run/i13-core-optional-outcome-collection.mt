// profiles: debug release
import alloc.vec.List
import core.iter
import core.outcome

static mut DROPS: usize = 0usize

type Tracked {
    value: i32
    drop { unsafe { DROPS += 1usize } }
}

fn main(): i32 {
    var optional_polls = 0usize
    let optional: List<Tracked>? = iter.from_fn(fn(): (Tracked?)? {
        optional_polls += 1usize
        if optional_polls == 1usize { present(present(Tracked(11))) }
        else if optional_polls == 2usize { present(none) }
        else { core.panic.panic("optional collection polled after none") }
    }).collect()
    if optional.is_present() || optional_polls != 2usize { return 1 }
    if unsafe { DROPS != 1usize } { return 2 }

    var outcome_polls = 0usize
    let outcome: (Outcome<List<Tracked>, i32>) =
        iter.from_fn(fn(): (Outcome<Tracked, i32>)? {
            outcome_polls += 1usize
            if outcome_polls == 1usize { present(success(Tracked(22))) }
            else if outcome_polls == 2usize { present(failure(73i32)) }
            else { core.panic.panic("outcome collection polled after failure") }
        }).collect()
    match outcome {
        success(_) => { return 3 },
        failure(error) => { if error != 73 { return 4 } }
    }
    if outcome_polls != 2usize { return 5 }
    if unsafe { DROPS != 2usize } { return 6 }
    0
}
