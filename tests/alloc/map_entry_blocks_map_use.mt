// expect-error: ownership
import alloc.hash_map.Entry

fn main(): i32 {
    var map = alloc.hash_map.new<i32, i32>()
    {
        let initial = map.or_insert(1, 10)
        if *initial != 10 { return 1 }
    }
    let entry = map.entry(1)
    if map.contains_key(1) { return 2 }
    match take entry {
        Entry.Occupied(occupied) => { if *occupied.get() != 10 { return 3 } },
        Entry.Vacant(_) => { return 4 }
    }
    0
}
