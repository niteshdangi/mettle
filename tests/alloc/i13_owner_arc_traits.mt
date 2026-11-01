import alloc.string.String
import alloc.rc
import core.clone.Clone
import core.cmp.{ Ord, Ordering }
import core.fmt
import core.fmt.{ Debug, Display }
import core.hash
import core.hash.{ Hash, Hasher }

fn render_display<T: Display>(value: read T): String {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Display).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { return alloc.string.new() }
        }
    }
    output
}

fn render_debug<T: Debug>(value: read T): String {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { return alloc.string.new() }
        }
    }
    output
}

fn main(): i32 {
    let first = alloc.arc.new(41)
    let retained = first.clone()
    let distinct_equal = alloc.arc.new(41)
    let greater = alloc.arc.new(42)
    if first != retained || first != distinct_equal ||
        first.ptr_eq(distinct_equal) {
        return 1
    }
    if first.cmp(distinct_equal) != Ordering.Equal ||
        greater <= first || first >= greater {
        return 2
    }

    var owner_hash = hash.fnv1a()
    var payload_hash = hash.fnv1a()
    first.hash(mut owner_hash)
    41.hash(mut payload_hash)
    if owner_hash.finish() != payload_hash.finish() { return 3 }

    if render_display(greater).as_text() != "42" ||
        render_debug(greater).as_text() != "42" {
        return 4
    }

    let local_left = unsafe {
        alloc.rc.new_zeroed_slice<i32>(2usize).assume_init()
    }
    let local_right = unsafe {
        alloc.rc.new_zeroed_slice<i32>(2usize).assume_init()
    }
    if local_left != local_right || local_left.ptr_eq(local_right) ||
        local_left.cmp(local_right) != Ordering.Equal ||
        render_debug(local_left).as_text() != "[0, 0]" {
        return 5
    }

    let atomic_left = unsafe {
        alloc.arc.new_zeroed_slice<i32>(2usize).assume_init()
    }
    let atomic_right = unsafe {
        alloc.arc.new_zeroed_slice<i32>(2usize).assume_init()
    }
    if atomic_left != atomic_right || atomic_left.ptr_eq(atomic_right) ||
        atomic_left.cmp(atomic_right) != Ordering.Equal ||
        render_debug(atomic_left).as_text() != "[0, 0]" {
        return 6
    }
    0
}
