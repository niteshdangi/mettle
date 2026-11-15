// profiles: debug release
import core.slice
import core.iter
import alloc.vec

type Item { value: i32 }

fn main(): i32 {
    let values = [10, 20, 30, 40]
    let first: read i32
    let last: read i32
    {
        var view: read [i32] = read values[..]
        first = slice.split_off_first(mut view).or_panic()
        last = slice.split_off_last(mut view).or_panic()
        assert(*first == 10 && *last == 40, "read endpoints")
        assert(view.len() == 2usize && view[0usize] == 20 && view[1usize] == 30,
            "stored read view retains the middle")
        assert(*slice.split_off_last(mut view).or_panic() == 30, "second last")
        assert(*slice.split_off_first(mut view).or_panic() == 20, "last remaining element")
        assert(view.len() == 0usize && slice.split_off_first(mut view).is_none() &&
            slice.split_off_last(mut view).is_none(), "empty endpoints preserve empty view")
    }
    assert(*first + *last == 50 && values.len() == 4usize,
        "results outlive the holder without shortening the owner")
    {
        var view: read [i32] = read values[..]
        let prefix = slice.split_off(mut view, iter.range_to(2usize)).or_panic()
        assert(prefix.len() == 2usize && prefix[0usize] == 10 &&
            view.len() == 2usize && view[0usize] == 30, "read prefix")
        let suffix = slice.split_off(mut view, core.range.RangeFrom(1usize)).or_panic()
        assert(suffix.len() == 1usize && suffix[0usize] == 40 &&
            view.len() == 1usize && view[0usize] == 30, "read suffix")
        assert(slice.split_off(mut view, core.range.RangeToInclusive(usize.MAX)).is_none() &&
            view.len() == 1usize, "overflow leaves read view unchanged")
        assert(slice.split_off(mut view, core.range.RangeToInclusive(0usize)).or_panic().len() == 1usize &&
            view.is_empty(), "inclusive read prefix")
    }
    let items = vec.from_array([Item(7), Item(8), Item(9)])
    let front: read Item
    let back: read Item
    {
        var view: read [Item] = items.as_slice()
        front = slice.split_off_first(mut view).or_panic()
        back = slice.split_off_last(mut view).or_panic()
        assert(view.len() == 1usize && view[0usize].value == 8,
            "List-derived view retains non-Copy elements")
    }
    assert(front.value == 7 && back.value == 9 && items.len() == 3usize,
        "List endpoints retain the original owner region")
    let units = [(); 3]
    var zero: read [Unit] = read units[..]
    assert(!slice.split_off_first(mut zero).is_none() &&
        !slice.split_off_last(mut zero).is_none() && zero.len() == 1usize,
        "zero-sized elements partition logical positions")
    0
}
