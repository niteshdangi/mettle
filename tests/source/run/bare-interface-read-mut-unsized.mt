// A bare interface parameter accessed through read or mut is only borrowed,
// so unsized implementors (Text, slices) are accepted.
interface Weigh { fn weight(): usize; }
extend Text implements Weigh { fn weight(): usize { self.len() } }
extend<T> [T] implements Weigh { fn weight(): usize { self.len() } }
type Counter { n: usize }
extend Counter implements Weigh { fn weight(): usize { self.n } }

fn by_read(item: read Weigh): usize { item.weight() }
fn by_default(item: Weigh): usize { item.weight() }
fn by_take(item: take Weigh): usize { item.weight() }
fn of_slice(items: read [u8]): usize { by_read(items) }
fn twice(a: read Weigh, b: read Weigh): usize { a.weight() + b.weight() }

fn main(): i32 {
    let words = [1u8, 2u8, 3u8]
    let counter = Counter(4usize)
    let total = by_read("ab") + by_default("cde") + of_slice(words) + by_take(Counter(4usize)) + twice("x", counter)
    if total == 2usize + 3usize + 3usize + 4usize + 1usize + 4usize { 0 } else { 1 }
}
