// expect-error: ownership 10:47 live exclusive loan
import core.slice

fn main(): i32 {
    var values = [1, 2, 3]
    var view: mut [i32] = mut values[..]
    var total = 0
    while view.len() > 1usize {
        let held = mut view[0usize]
        let first = slice.split_off_first_mut(mut view).or_panic()
        *held += *first
        total += *held
    }
    total
}
