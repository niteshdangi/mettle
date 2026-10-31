// expect-error: ownership 8:5 live read loan
import alloc.vec

fn main(): i32 {
    var values = vec.new<i32>()
    values.push(10)
    let first = values.get(0usize)
    values.push(20)
    match first {
        present(value) => { if *value != 10 { return 1 } },
        none => { return 2 }
    }
    0
}
