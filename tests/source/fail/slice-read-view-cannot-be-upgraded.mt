// expect-error: ownership 7:15 mutable

fn increment(values: mut [i32]) { values[0] += 1 }
fn main() {
    var values = [41]
    let borrowed: read [i32] = read values
    increment(borrowed)
    0
}
