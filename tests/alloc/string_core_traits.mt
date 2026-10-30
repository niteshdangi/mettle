import alloc.string.String;
import core.clone.Clone;
import core.cmp.{Ordering, Ord};
import core.hash;
import core.hash.{Hash, Hasher};
import core.fmt;
import core.fmt.{Write, Display, Debug};
import core.text.Text;

fn main(): i32 {
    var s = alloc.string.from_text("héllo")
    var t = alloc.string.new()
    {
        var f = fmt.formatter(mut t, fmt.spec())
        match capture String.(Display).fmt(s, mut f) { success(u) => {}, failure(e) => { return 1 } }
    }
    if t != s { return 2 }
    var h1 = hash.fnv1a()
    var h2 = hash.fnv1a()
    s.hash(mut h1)
    s.as_text().hash(mut h2)
    if h1.finish() != h2.finish() { return 3 }
    if s.len() != 6usize || !s.starts_with("hé") { return 4 }
    let part = read s[0..3]
    if part != "hé" { return 5 }
    match capture fmt.write(mut t, 42) { success(u) => {}, failure(e) => { return 6 } }
    if t.as_text() != "héllo42" { return 7 }
    var d = alloc.string.new()
    {
        var f = fmt.formatter(mut d, fmt.spec())
        match capture String.(Debug).fmt(s, mut f) { success(u) => {}, failure(e) => { return 8 } }
    }
    if d.as_text() != "\"héllo\"" { return 9 }
    if s.cmp(read t) != Ordering.Less { return 10 }
    0
}
