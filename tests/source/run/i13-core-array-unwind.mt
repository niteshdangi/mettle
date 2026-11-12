// profiles: debug release
import core.array
import std.panic.{catch_panic, CatchResult}

static mut INPUT_DROPS: usize = 0usize
static mut OUTPUT_DROPS: usize = 0usize
static mut CALLS: usize = 0usize
type Input {
    value: usize
    drop { unsafe { INPUT_DROPS += 1usize } }
}
type Output {
    drop { unsafe { OUTPUT_DROPS += 1usize } }
}

fn main(): i32 {
    let construction = catch_panic(fn(): Unit {
        let values: [Output; 4] = array.from_fn(fn(index: usize): Output {
            unsafe { CALLS += 1usize }
            if index == 2usize { panic("construction stopped") }
            Output()
        })
    })
    match construction {
        CatchResult.Panicked(info) => {
            if info.message() != "construction stopped" { return 1 }
        },
        CatchResult.Returned(_) => { return 2 }
    }
    if unsafe { OUTPUT_DROPS != 2usize || CALLS != 3usize } { return 3 }
    unsafe { OUTPUT_DROPS = 0usize; CALLS = 0usize }
    let mapping = catch_panic(fn(): Unit {
        let values = [Input(0usize), Input(1usize), Input(2usize), Input(3usize)]
        let mapped = values.map(fn(take value: Input): Output {
            unsafe { CALLS += 1usize }
            if value.value == 2usize { panic("mapping stopped") }
            Output()
        })
    })
    match mapping {
        CatchResult.Panicked(info) => {
            if info.message() != "mapping stopped" { return 4 }
        },
        CatchResult.Returned(_) => { return 5 }
    }
    if unsafe { INPUT_DROPS != 4usize || OUTPUT_DROPS != 2usize || CALLS != 3usize } {
        return 6
    }
    {
        let values: [Output; 3] = array.from_fn(fn(index: usize): Output { Output() })
    }
    if unsafe { OUTPUT_DROPS != 5usize } { return 7 }
    0
}
