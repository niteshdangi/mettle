import core.iter.{Iterator, Iterable, MutableIterable}

fn first<C: Iterable + unsized>(c: read C): (read C.Item from c)? {
    var it = c.iter()
    it.next()
}

fn first_mut<C: MutableIterable + unsized>(c: mut C): (mut C.Item from c)? {
    var it = c.iter_mut()
    it.next()
}

fn main(): i32 {
    var values = [3, 5]
    match first(read values[0usize..2usize]) {
        present(x) => { if *x != 3 { return 1 } },
        none => { return 2 }
    }
    match take first_mut(mut values[0usize..2usize]) {
        present(x) => { *x += 1 },
        none => { return 3 }
    }
    if values[0usize] != 4 || values[1usize] != 5 { return 4 }
    match first(read values[0usize..0usize]) {
        present(x) => { return 5 },
        none => {}
    }
    0
}
