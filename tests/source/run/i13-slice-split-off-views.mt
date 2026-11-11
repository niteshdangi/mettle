// profiles: debug release
import core.slice
import core.iter
import alloc.vec

type Item { value: i32 }

fn main(): i32 {
    var values = [10, 20, 30, 40, 50, 60]
    {
        var view: mut [i32] = mut values[..]
        let front = slice.split_off_first_mut(mut view).unwrap()
        let back = slice.split_off_last_mut(mut view).unwrap()
        *front = 11
        *back = 61
        view[0usize] = 21
        assert(*front == 11 && *back == 61 && view.len() == 4usize,
            "exclusive endpoint and remainder loans coexist")
    }
    assert(values[0usize] == 11 && values[1usize] == 21 && values[5usize] == 61,
        "backing owner is neither shortened nor moved")
    let prefix: mut [i32]
    {
        var view: mut [i32] = mut values[..]
        prefix = slice.split_off_mut(mut view, iter.range_to(2usize)).unwrap()
        let suffix = slice.split_off_mut(mut view, iter.range_from(2usize)).unwrap()
        assert(prefix.len() == 2usize && view.len() == 2usize && suffix.len() == 2usize,
            "prefix and suffix selection retain complementary views")
        prefix[0usize] = 12
        view[0usize] = 31
        suffix[0usize] = 51
    }
    prefix[1usize] = 22
    assert(values[0usize] == 12 && values[1usize] == 22 &&
        values[2usize] == 31 && values[4usize] == 51,
        "range result retains original region after holder destruction")
    {
        var view: mut [i32] = mut values[..]
        assert(slice.split_off_mut(mut view, iter.range_to(7usize)).is_none(), "invalid prefix")
        assert(slice.split_off_mut(mut view, iter.range_from(7usize)).is_none(), "invalid suffix")
        assert(slice.split_off_mut(mut view, iter.range_to_inclusive(0xffffffffffffffffusize)).is_none(),
            "inclusive end never wraps")
        assert(view.len() == 6usize && view[0usize] == 12, "invalid bounds preserve view")
        let included = slice.split_off_mut(mut view, iter.range_to_inclusive(1usize)).unwrap()
        assert(included.len() == 2usize && view.len() == 4usize, "inclusive prefix")
        let empty_prefix = slice.split_off_mut(mut view, iter.range_to(0usize)).unwrap()
        assert(empty_prefix.len() == 0usize && view.len() == 4usize, "empty prefix")
        let empty_suffix = slice.split_off_mut(mut view, iter.range_from(4usize)).unwrap()
        assert(empty_suffix.len() == 0usize && view.len() == 4usize, "empty suffix")
        let all = slice.split_off_mut(mut view, iter.range_to(4usize)).unwrap()
        assert(all.len() == 4usize && view.len() == 0usize, "full prefix")
        assert(slice.split_off_first_mut(mut view).is_none() &&
            slice.split_off_last_mut(mut view).is_none(), "empty exclusive endpoints")
    }
    {
        var zero = [(); 3]
        var view: mut [Unit] = mut zero[..]
        let front = slice.split_off_first_mut(mut view).unwrap()
        let back = slice.split_off_last_mut(mut view).unwrap()
        *front = ()
        *back = ()
        assert(view.len() == 1usize, "zero-sized endpoints partition logical elements")
    }
    {
        var backing = [1, 2, 3]
        var view: mut [i32] = mut backing[..]
        var total = 0
        while view.len() != 0usize {
            let first = slice.split_off_first_mut(mut view).unwrap()
            if view.len() != 0usize { view[0usize] += 10 }
            total += *first
        }
        assert(total == 26, "each loop result is disjoint from its updated remainder")
    }
    {
        var list = vec.new<Item>()
        list.push(Item(1))
        list.push(Item(2))
        list.push(Item(3))
        let first: mut Item
        {
            var view: mut [Item] = list.as_mut_slice()
            first = slice.split_off_first_mut(mut view).unwrap()
            let last = slice.split_off_last_mut(mut view).unwrap()
            view[0usize].value = 20
            last.value = 30
        }
        first.value = 10
        assert(list.len() == 3usize && list[0usize].value == 10 &&
            list[1usize].value == 20 && list[2usize].value == 30,
            "non-Copy List elements retain the owner's region beyond the holder")
    }
    0
}
