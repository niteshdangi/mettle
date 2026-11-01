// profiles: debug release
// expect-error-count: 1
// expect-error: type 9:8 unsatisfied interface bound 'Static'
import core.any

fn main(): i32 {
    let number = 7
    let borrowed = read number
    if any.is<read i32 from static>(read borrowed) { 1 } else { 0 }
}
