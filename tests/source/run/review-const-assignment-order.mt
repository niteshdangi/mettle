const fn assign(compound: bool): i32 {
    var values = [0i8]
    var order = 0
    if compound {
        values[{ order = order * 10 + 1; 0usize }] += {
            order = order * 10 + 2
            3
        }
    } else {
        values[{ order = order * 10 + 1; 0usize }] = {
            order = order * 10 + 2
            3
        }
    }
    order * 10 + values[0usize] as i32
}
const PLAIN: i32 = assign(false)
const COMPOUND: i32 = assign(true)
fn main(): i32 {
    if PLAIN == 213 && COMPOUND == 213 { 0 } else { 1 }
}
