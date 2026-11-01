// expect-error: ownership 11:5 access or storage lifetime conflicts
import core.iter
import core.iter.Iterator

fn main(): i32 {
    var values = [1, 2]
    var source = iter.once(read values[0usize]).chain(iter.once(read values[1usize]))
    let first = match take source.next() {
        present(item) => item, none => { return 1 }
    }
    values[0usize] = 9
    if *first != 1 { return 2 }
    0
}
