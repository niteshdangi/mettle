// profiles: debug release
import core.iter
import core.iter.{ Iterator, BidirectionalIterator }

fn pull<T, I: Iterator<Item = T>>(mut items: I): T? {
    items.next()
}

fn main(): i32 {
    var values = [4, 7, 9, 12]
    {
        var source = iter.once(read values[0usize]).chain(iter.once(read values[1usize]))
        let first = match take pull(mut source) {
            present(item) => item, none => { return 1 }
        }
        let second = match take source.next() {
            present(item) => item, none => { return 2 }
        }
        assert(*first == 4 && *second == 7, "both halves preserve carried views")
        assert(source.next().is_none(), "forward exhaustion")
    }
    {
        var source = iter.once(read values[2usize]).chain(iter.once(read values[3usize]))
        let last = match take source.next_back() {
            present(item) => item, none => { return 3 }
        }
        let first = match take source.next() {
            present(item) => item, none => { return 4 }
        }
        assert(*first == 9 && *last == 12, "mixed traversal preserves carried views")
        assert(source.next_back().is_none(), "backward exhaustion")
    }
    values[0usize] = 20
    assert(values[0usize] == 20, "expired iterator views do not retain input")
    0
}
