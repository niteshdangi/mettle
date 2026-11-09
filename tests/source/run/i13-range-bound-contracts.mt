// profiles: debug release
import core.iter
import core.iter.{Bound, RangeBounds, Iterator}
import core.clone.Clone
import core.text.Text

enum Endpoint<T> { Included(T), Unbounded }
interface Endpoints<T> {
    fn first(): Endpoint<read T from self>;
}
type NoEndpoints {}
extend NoEndpoints implements Endpoints<i32> {
    fn first(): Endpoint<read i32 from self> { Endpoint.Unbounded }
}

fn lower<T: unsized, R: RangeBounds<T>>(read range: R): Bound<read T from range> {
    range.start_bound()
}

fn text_contains<R: RangeBounds<Text>>(read range: R, read value: Text): bool {
    range.contains(read value)
}

fn main(): i32 {
    match take NoEndpoints().first() {
        Endpoint.Unbounded => {},
        _ => { return 1 }
    }
    let range = iter.range(2, 5)
    assert(!range.contains(1) && range.contains(2) && range.contains(4) && !range.contains(5), "half open bounds")
    match take lower<i32>(read range) {
        Bound.Included(value) => assert(*value == 2, "generic bound carries receiver view"),
        _ => { return 2 }
    }
    let custom = (Bound.Excluded(2), Bound.Included(5))
    assert(!custom.contains(2) && custom.contains(3) && custom.contains(5), "mixed endpoint tuple")
    let from = iter.range_from(3)
    assert(!from.contains(2) && from.contains(3) && from.contains(i32.MAX), "unbounded upper")
    let to = iter.range_to(3)
    assert(to.contains(i32.MIN) && !to.contains(3), "unbounded lower")
    let to_inclusive = iter.range_to_inclusive(3)
    assert(to_inclusive.contains(3) && !to_inclusive.contains(4), "inclusive upper")
    var closed = iter.range_inclusive(7, 7)
    assert(closed.contains(7), "singleton inclusive bounds")
    assert(closed.next() == present(7), "singleton yield")
    assert(!closed.contains(7), "exhausted inclusive bounds are empty")
    let empty = iter.range(5, 2)
    assert(!empty.contains(3), "reversed bounds empty")
    let floating = iter.Range(0.0f64, 2.0f64)
    let unordered = 0.0f64 / 0.0f64
    assert(floating.contains(1.0f64) && !floating.contains(unordered), "unordered query rejected")
    let bound = Bound.Included(4)
    match take bound.as_ref() {
        Bound.Included(value) => assert(*value == 4, "bound borrowed payload"),
        _ => { return 3 }
    }
    match take bound.clone().map(fn(take value: i32): i32 { value + 1 }) {
        Bound.Included(value) => assert(value == 5, "bound map preserves inclusion"),
        _ => { return 4 }
    }
    let unrestricted = iter.range_full()
    assert(iter.RangeFull.(RangeBounds<i32>).contains(read unrestricted, 9), "fully unbounded")
    let text_range = iter.range("apple", "pear")
    assert(text_contains(read text_range, "banana") && !text_contains(read text_range, "pear"), "unsized borrowed range query")
    let text_bounds = (Bound.Excluded("apple"), Bound.Included("pear"))
    assert(!text_contains(read text_bounds, "apple") && text_contains(read text_bounds, "pear"), "borrowed endpoint tuple")
    match take lower<Text>(read text_range) {
        Bound.Included(value) => assert(value.len() == 5usize, "unsized endpoint metadata"),
        _ => { return 5 }
    }
    0
}
