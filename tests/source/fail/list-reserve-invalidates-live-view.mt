// expect-error: ownership 8:5 live read loan
import alloc.vec

fn main() {
    var values = vec.new<i32>()
    values.push(1)
    let view = values.as_slice()
    values.reserve(8usize)
    *view
}
