// profiles: debug release
import core.iter.OwnedIterable
import std.path.{Path, PathBuf, path_buf_from_text, path_from_text}

fn total<I: OwnedIterable<Item = i32>>(take items: I): i32 {
    var source: I.(OwnedIterable).IntoIter = I.(OwnedIterable).into_iter(items)
    var sum = 0
    while true {
        match take source.next() {
            present(value) => { sum += value },
            none => { break }
        }
    }
    sum
}

fn path_parts<region r>(take items: read Path from r): usize {
    var source = items.into_iter()
    var count = 0usize
    while source.next().is_present() { count += 1usize }
    count
}

fn owned_path_parts<region r>(take items: read PathBuf from r): usize {
    var source = items.into_iter()
    var count = 0usize
    while source.next().is_present() { count += 1usize }
    count
}

fn main(): i32 {
    let some: i32? = present(4)
    let none_value: i32? = none
    let good: (Outcome<i32, i32>) = success(5)
    let bad: (Outcome<i32, i32>) = failure(1)
    if total(some) != 4 || total(none_value) != 0 || total(good) != 5 || total(bad) != 0 { return 1 }

    var values = [1, 2, 3]
    var slice: mut [i32] = mut values
    var seen = 0
    for value in read slice { seen += value }
    for value in mut slice { value += 1 }
    if seen != 6 || values[2usize] != 4 { return 2 }

    let path = path_from_text("/a/b/c")
    let owned = path_buf_from_text("/a/b")
    if path_parts(path) != 4usize || owned_path_parts(read owned) != 3usize { return 3 }
    0
}
