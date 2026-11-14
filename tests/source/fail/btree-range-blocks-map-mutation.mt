// expect-error: ownership 10:5 live read loan
import alloc.btree

fn main(): i32 {
    var tree = btree.new<i32, i32>()
    tree.insert(1, 10)
    tree.insert(2, 20)
    var entries = tree.range(core.iter.range(1, 3))
    let first = entries.next()
    tree.insert(3, 30)
    match first {
        present(entry) => { if entry.value != 10 { return 1 } },
        none => { return 2 }
    }
    match entries.next() {
        present(_) => {},
        none => {}
    }
    0
}
