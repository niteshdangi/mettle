// A read parameter of an unsized type may default to a literal view.
static TABLE: [i32; 3] = [1, 2, 3]
fn width(read message: Text = "fallback"): usize { message.len() }
fn total(read items: [i32] = read TABLE): i32 { items[0] + items[1] + items[2] }
fn after(read prefix: Text = "ab", count: usize = 2): usize { prefix.len() + count }

fn main(): i32 {
    let ok = width() == 8usize && width("abc") == 3usize &&
             total() == 6 && total([4, 5, 0]) == 9 &&
             after() == 4usize && after("xyz") == 5usize && after("x", 7usize) == 8usize
    if ok { 0 } else { 1 }
}
