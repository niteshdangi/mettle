// profiles: debug release
import alloc.vec_deque
import core.cmp.Eq
import core.fmt.{Debug, Error, buffer_writer, formatter, spec, written_text}
import core.hash.{Hash, hash_one}
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator, OwnedIterable}

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn render<T: Debug>(value: read T, buffer: mut [u8]): usize throws Error {
    var out = buffer_writer(mut buffer)
    var f = formatter(mut out, spec())
    try value.fmt(mut f)
    out.len()
}

fn require_eq<T: Eq>(value: read T): bool { true }

fn run(): i32 throws Error {
    var buffer = [0u8; 64]
    var deque = vec_deque.new<i32>()
    deque.push_back(1)
    deque.push_back(2)
    deque.push_front(0)
    let written = try render(read deque, mut buffer)
    match written_text(read buffer, written) {
        present(text) => { if text != "[0, 1, 2]" { return 1 } },
        none => { return 2 }
    }
    var empty = vec_deque.new<i32>()
    let empty_written = try render(read empty, mut buffer)
    match written_text(read buffer, empty_written) {
        present(text) => { if text != "[]" { return 3 } },
        none => { return 4 }
    }

    var same = vec_deque.new<i32>()
    same.push_back(0)
    same.push_back(1)
    same.push_back(2)
    if hash_one(read deque) != hash_one(read same) { return 5 }
    var other = vec_deque.new<i32>()
    other.push_back(2)
    other.push_back(1)
    other.push_back(0)
    if hash_one(read deque) == hash_one(read other) { return 6 }
    if !require_eq(read deque) { return 7 }

    // Fallible pushes succeed without changing the ordering rules.
    match capture deque.try_push_back(3) {
        success(_) => {},
        failure(_) => { return 8 }
    }
    match capture deque.try_push_front(-1) {
        success(_) => {},
        failure(_) => { return 9 }
    }
    if deque.len() != 5usize || deque[0usize] != -1 || deque[4usize] != 3 { return 10 }
    deque.shrink_to_fit()
    if deque.capacity() != 5usize { return 11 }

    // IntoIter from both ends, with size hints that track remaining items.
    var owned = vec_deque.new<i32>()
    owned.push_back(1)
    owned.push_back(2)
    owned.push_back(3)
    var items = owned.into_iter()
    if items.size_hint() != (3usize, present(3usize)) { return 12 }
    match take items.next_back() {
        present(value) => { if value != 3 { return 13 } },
        none => { return 14 }
    }
    match take items.next() {
        present(value) => { if value != 1 { return 15 } },
        none => { return 16 }
    }
    if items.size_hint() != (1usize, present(1usize)) { return 17 }
    match take items.next() {
        present(value) => { if value != 2 { return 18 } },
        none => { return 19 }
    }
    if items.next().is_present() || items.next_back().is_present() { return 20 }

    // Iter over a borrowed deque (ExactSizeIterator and DoubleEndedIterator).
    var walk = deque.iter()
    if walk.size_hint() != (5usize, present(5usize)) { return 21 }
    match take walk.next() {
        present(value) => { if *value != -1 { return 22 } },
        none => { return 23 }
    }
    match take walk.next_back() {
        present(value) => { if *value != 3 { return 24 } },
        none => { return 25 }
    }
    if walk.size_hint() != (3usize, present(3usize)) { return 26 }
    return 0
}

// Dropping a deque drops its live elements; an abandoned drain drops the
// unyielded range and the tail, and the surviving elements keep their order.
fn drop_checks(): i32 {
    var drops = 0usize
    {
        var full = vec_deque.new<Counted>()
        full.push_back(Counted(1, core.ptr.from_mut(drops)))
        full.push_back(Counted(2, core.ptr.from_mut(drops)))
        full.push_back(Counted(3, core.ptr.from_mut(drops)))
        full.push_back(Counted(4, core.ptr.from_mut(drops)))
        {
            var drain = full.drain(1usize..3usize)
            match take drain.next() {
                present(item) => { if item.value != 2 { return 1 } },
                none => { return 2 }
            }
        }
        if drops != 2usize { return 3 }
        if full.len() != 2usize || full[0usize].value != 1 || full[1usize].value != 4 {
            return 4
        }
    }
    if drops != 4usize { return 5 }
    0
}

fn main(): i32 {
    let drop_code = drop_checks()
    if drop_code != 0 { return drop_code }
    match take capture run() { success(code) => code, failure(_) => 99 }
}
