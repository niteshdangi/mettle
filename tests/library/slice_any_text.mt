import core.slice
import core.iter
import core.iter.Iterator
import core.option
import core.any
import core.text

type P { x: i32 }

interface Arity { fn arity(): usize; }
extend<T> [T; 3] implements Arity { fn arity(): usize { 3usize } }

fn pick(c: bool): read text.Text from static { if c { "a" } else { "b" } }

copy type Raw { data: ptr<read u8>; len: usize }
type Cursor<region r> { buffer: mut [u8] from r; length: usize }
extend<region r> Cursor<region r> {
    fn view(): read text.Text from self {
        let fat = core.ptr.from_ref(read *self.buffer)
        let raw = unsafe { core.mem.transmute<Raw>(fat) }
        let out = unsafe { core.mem.transmute<ptr<read text.Text>>(Raw(raw.data, self.length)) }
        unsafe { read *out }
    }
}

// A sub-slice rebuilt from raw parts keeps the iterator's declared region.
pub type Pairs<region r> { items: read [u8] from r; base: ptr<read u8>; index: usize }
extend<region r> Pairs<region r> implements Iterator {
    type Item = read [u8] from r
    mut fn next(): (read [u8] from r)? {
        let part = unsafe { core.mem.transmute<ptr<read [u8]>>(Raw(self.base, 1usize)) }
        present(unsafe { read *part })
    }
}

fn first_item<T>(read items: [T]): (read T from items)? {
    var it = items.iter()
    it.next()
}

fn count<I: Iterator>(take it: I): usize {
    var n = 0usize
    var i = it
    while true { match i.next() { present(x) => { n += 1usize }, none => { break } } }
    n
}

fn main(): i32 {
    var xs = [5, 3, 9, 1, 7, 3, 0]
    let v = mut xs
    v.sort_unstable()
    if !xs.is_sorted() || xs[0] != 0 || xs[6] != 9 { return 1 }
    var e = [0; 0]
    let ev = mut e
    ev.sort_unstable()
    var one = [4]
    let ov = mut one
    ov.sort_unstable()
    let r = read xs
    let k7 = 7
    let k4 = 4
    let pre = [0, 1]
    if !r.contains(read k7) || r.contains(read 11) { return 2 }
    match capture r.binary_search(read k7) { success(i) => { if i != 5usize { return 3 } }, failure(i) => { return 3 } }
    match capture r.binary_search(read k4) { success(i) => { return 4 }, failure(i) => { if i != 4usize { return 4 } } }
    if !r.starts_with(read pre) { return 5 }
    match r.first() { present(f) => { if *f != 0 { return 6 } }, none => { return 6 } }
    match r.last() { present(f) => { if *f != 9 { return 6 } }, none => { return 6 } }
    match r.get(7usize) { present(f) => { return 7 }, none => {} }
    var a = [1, 2, 3, 4, 5]
    let rv = mut a
    rv.reverse()
    if a[0] != 5 || a[4] != 1 { return 8 }
    let sw = mut a
    sw.swap(0usize, 4usize)
    sw.swap(2usize, 2usize)
    if a[0] != 1 || a[4] != 5 || a[2] != 3 { return 9 }
    let fl = mut a
    fl.fill(7)
    if a[0] != 7 || a[4] != 7 { return 10 }
    let src = [9, 8, 7, 6, 5]
    let cp = mut a
    cp.copy_from_slice(read src)
    if a[1] != 8 { return 11 }
    let parts_src = mut a
    let parts = parts_src.split_at_mut(2usize)
    var l = parts.0
    var rr = parts.1
    l[0] = 10
    rr[0] = 30
    if a[0] != 10 || a[2] != 30 { return 12 }
    let rd = read a
    let halves = rd.split_at(3usize)
    if halves.0.len() != 3usize || halves.1.len() != 2usize { return 13 }
    var n = 0usize
    while true { match rd.window(n, 2usize) { present(w) => { n += 1usize }, none => { break } } }
    var m = 0usize
    var last = 0usize
    while true { match rd.chunk(m, 2usize) { present(c) => { m += 1usize; last = c.len() }, none => { break } } }
    if n != 4usize || m != 3usize || last != 1usize { return 14 }
    var total = 0
    var it = rd.iter()
    while true { match it.next() { present(x) => { total += *x }, none => { break } } }
    var bump = mut a
    var im = bump.iter_mut()
    while true { match take im.next() { present(x) => { *x += 1 }, none => { break } } }
    if total != 10 + 8 + 30 + 6 + 5 || a[0] != 11 { return 15 }
    // any
    let num = 5
    if !any.is<i32>(read num) || any.is<u32>(read num) { return 16 }
    match any.downcast_ref<i32>(read num) { present(d) => { if *d != 5 { return 17 } }, none => { return 17 } }
    match any.downcast_ref<u8>(read num) { present(d) => { return 18 }, none => {} }
    var p = P(1)
    match take any.downcast_mut<P>(mut p) { present(d) => { d.x = 9 }, none => { return 19 } }
    if p.x != 9 || any.type_id<P>() == any.type_id<i32>() { return 20 }
    // text
    let s = "  h\u{e9}llo, w\u{f6}rld \n"
    if s.trim() != "h\u{e9}llo, w\u{f6}rld" || s.trim_end().len() != s.len() - 2usize || "   ".trim() != "" { return 21 }
    match "a=b=c".split_once("=") { present(q) => { if q.0 != "a" || q.1 != "b=c" { return 22 } }, none => { return 22 } }
    match "abc".split_once("x") { present(q) => { return 23 }, none => {} }
    match "hello".find("ll") { present(i) => { if i != 2usize { return 24 } }, none => { return 24 } }
    match "hello".find("") { present(i) => { if i != 0usize { return 25 } }, none => { return 25 } }
    match "hello".find("hellos") { present(i) => { return 26 }, none => {} }
    if !"hello".ends_with("llo") || "hello".ends_with("xllo") || !"hello".contains("ell") { return 27 }
    var ci = "a\u{e9}!".char_indices()
    var acc = 0usize
    while true { match ci.next() { present(q) => { acc = acc * 10usize + q.0 }, none => { break } } }
    if acc != 13usize { return 28 }
    if count("a,b,,c".split(",")) != 4usize || count("".split(",")) != 1usize || count("abc".split("")) != 1usize { return 29 }
    if count("x\ny\r\nz\n".lines()) != 3usize || count("".lines()) != 0usize || count("\n".lines()) != 1usize { return 30 }
    var l2 = "ab\r\ncd".lines()
    match l2.next() { present(q) => { if q != "ab" { return 31 } }, none => { return 31 } }
    match l2.next() { present(q) => { if q != "cd" { return 32 } }, none => { return 32 } }
    match l2.next() { present(q) => { return 33 }, none => {} }
    // generic array impls, text-literal branches, raw-part views, local iterators
    if [1, 2, 3].arity() != 3usize || pick(true) != "a" || pick(false) != "b" { return 34 }
    var bytes = [104u8, 105u8, 0u8]
    let cursor = Cursor(mut bytes, 2usize)
    if cursor.view() != "hi" { return 35 }
    let pair = [7, 8]
    match first_item<i32>(read pair) { present(q) => { if *q != 7 { return 36 } }, none => { return 36 } }
    0
}
