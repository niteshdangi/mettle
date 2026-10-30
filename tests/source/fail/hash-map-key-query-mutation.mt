// expect-error: ownership 11:21 live read loan
// A value borrowed through a text query lives on the map; mutating the map
// while it is alive is rejected.
import alloc.hash_map
import alloc.string
fn main(): i32 {
    var m = hash_map.new<string.String, i32>()
    let old = m.insert(string.from_text("a"), 1)
    match m.get("a") {
        present(v) => {
            let o = m.insert(string.from_text("b"), 2)
            if *v == 1 { return 0 }
        },
        none => {}
    }
    1
}
