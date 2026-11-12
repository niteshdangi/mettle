import core.iter.Iterator

interface BorrowedIterable: Sized {
    type Item;
    type IntoIter: Iterator<Item = Self.Item>;
    fn into_iter(receiver take self: Self): Self.IntoIter;
}

type Part { byte: u8 }
type Source { value: Part }
type Parts<region r> { value: read Part from r }

extend<region r> Parts<region r> implements Iterator {
    type Item = read Part from r
    mut fn next(): (read Part from r)? { present(self.value) }
}

extend<region r> read Source from r implements BorrowedIterable {
    type Item = read Part from r
    type IntoIter = Parts<region r>
    take fn into_iter(): Parts<region r> { Parts(read self.value) }
}

fn main(): i32 {
    let source = Source(Part(41u8))
    let borrowed = read source
    var parts = borrowed.into_iter()
    match parts.next() {
        present(value) => if value.byte == 41u8 { 0 } else { 1 },
        none => 2
    }
}
