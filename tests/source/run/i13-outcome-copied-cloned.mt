// profiles: debug release
// The outcome's copied/cloned on read and mut success views: the success value is
// copied or cloned, and the failure passes through unchanged (an owned,
// non-Copy failure is moved, not cloned).
import core.outcome
import alloc.string
import alloc.string.String
import core.clone.Clone

type Tally { count: i32 }
extend Tally implements Clone {
    fn clone(): Tally { Tally(self.count + 100) }
}

fn read_success<region r>(read value: i32 from r): (Outcome<(read i32 from r), String>) { success(read value) }
fn read_failure<region r>(read value: i32 from r): (Outcome<(read i32 from r), String>) { failure(string.from_text("lost")) }
fn mut_success<region r>(mut value: Tally from r): (Outcome<(mut Tally from r), i32>) { success(mut value) }
fn mut_failure<region r>(mut value: Tally from r): (Outcome<(mut Tally from r), i32>) { failure(5) }

fn main(): i32 {
    let base = 7
    match read_success(read base).copied() { success(v) => if v != 7 { return 1 }, failure(_) => { return 2 } }
    match read_success(read base).cloned() { success(v) => if v != 7 { return 3 }, failure(_) => { return 4 } }
    match take read_failure(read base).copied() {
        success(_) => { return 5 },
        failure(message) => if message.as_text() != "lost" { return 6 }
    }
    var tally = Tally(1)
    match mut_success(mut tally).cloned() {
        success(copy_of) => if copy_of.count != 101 { return 7 },
        failure(_) => { return 8 }
    }
    match mut_failure(mut tally).cloned() { success(_) => { return 9 }, failure(code) => if code != 5 { return 10 } }
    var counter = 3
    match mut_success_i32(mut counter).copied() { success(v) => if v != 3 { return 11 }, failure(_) => { return 12 } }
    if tally.count != 1 { return 13 }
    0
}

fn mut_success_i32<region r>(mut value: i32 from r): (Outcome<(mut i32 from r), i32>) { success(mut value) }
