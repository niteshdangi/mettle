module core {}

interface Stream {
    type Item
    mut fn next(): Self.Item?
}

type Counter { value: i32 }
extend Counter implements Stream {
    type Item = i32
    mut fn next(): i32? {
        let value = self.value
        self.value += 1
        present(value)
    }
}

extend<region r, I: Stream> mut I from r implements Stream {
    type Item = I.Item
    mut fn next(): I.Item? { I.(Stream).next(mut *self) }
}

fn first<I: Stream>(source: take I): I.Item? {
    var iterator = source
    iterator.next()
}

fn main(): i32 {
    var counter = Counter(13)
    match take first(mut counter) {
        present(value) => { if value != 13 { return 1 } },
        none => { return 2 }
    }
    if counter.value != 14 { return 3 }
    0
}
