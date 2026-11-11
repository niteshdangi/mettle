// expect-error: ownership 6:5 live exclusive loan
fn main(): i32 {
    var values = [10, 20]
    var view: mut [i32] = mut values[..]
    let first = core.slice.split_off_first_mut(mut view).unwrap()
    values[0usize] = 30
    *first
}
