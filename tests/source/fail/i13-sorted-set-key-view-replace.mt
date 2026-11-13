// expect-error: ownership 10:5 access or storage conflicts
import alloc.btree

fn main(): i32 {
    var values = btree.set_new<i32>()
    values.insert(1)
    let found = match values.get(1) {
        present(item) => item, none => { return 1 }
    }
    values.replace(1)
    if *found != 1 { return 2 }
    0
}
