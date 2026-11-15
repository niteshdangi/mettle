import core.cmp.Ordering
import core.iter.BidirectionalIterator
import core.iter.Iterator

fn main(): i32 {
    var values = [1, 2, 2, 3, 5]
    let slice = read values

    if slice.partition_point(fn(read x: i32): bool { x < 3 }) != 3usize {
        return 1
    }
    if !slice.is_sorted_by_key(fn(read x: i32): i32 { x }) ||
        !slice.is_sorted_by(fn(read a: i32, read b: i32): bool { a <= b }) {
        return 18
    }
    match capture slice.binary_search_by(fn(read x: i32): Ordering {
        if x < 2 { Ordering.Less } else if x > 2 { Ordering.Greater } else { Ordering.Equal }
    }) {
        success(index) => { if index < 1usize || index > 2usize { return 2 } },
        failure(_) => { return 2 }
    }
    let key = 3
    match capture slice.binary_search_by_key(read key, fn(read x: i32): i32 { x }) {
        success(index) => { if index != 3usize { return 3 } },
        failure(_) => { return 3 }
    }
    match slice.split_at_checked(5usize) {
        present(parts) => {
            if parts.0.len() != 5usize || !parts.1.is_empty() { return 4 }
        },
        none => { return 4 }
    }
    match slice.split_at_checked(6usize) {
        present(_) => { return 5 },
        none => {}
    }
    if slice.window(0xffffffffffffffffusize, 2usize).is_present() ||
        slice.chunk(0xffffffffffffffffusize, 2usize).is_present() {
        return 19
    }

    var read_iter = slice.iter()
    match read_iter.next() { present(x) => { if *x != 1 { return 6 } }, none => { return 6 } }
    match read_iter.next_back() { present(x) => { if *x != 5 { return 7 } }, none => { return 7 } }
    match read_iter.next_back() { present(x) => { if *x != 3 { return 8 } }, none => { return 8 } }
    match read_iter.next() { present(x) => { if *x != 2 { return 9 } }, none => { return 9 } }

    let byte_values = [10u8, 20u8, 30u8]
    let byte_slice: read [u8] = read byte_values
    var byte_iter = byte_slice.bytes()
    match byte_iter.next_back() {
        present(byte) => { if byte != 30u8 { return 10 } },
        none => { return 10 }
    }
    match byte_iter.next() {
        present(byte) => { if byte != 10u8 { return 11 } },
        none => { return 11 }
    }

    {
        let mutable = mut values
        match take mutable.get_mut(0usize) {
            present(x) => { *x = 9 },
            none => { return 12 }
        }
        match take mutable.split_at_mut_checked(2usize) {
            present(parts) => {
                var left = parts.0
                var right = parts.1
                left[1usize] = 8
                right[0usize] = 7
            },
            none => { return 13 }
        }
        match take mutable.split_at_mut_checked(6usize) {
            present(_) => { return 14 },
            none => {}
        }
        var mutable_iter = mutable.iter_mut()
        match take mutable_iter.next() {
            present(x) => { *x += 1 },
            none => { return 15 }
        }
        match take mutable_iter.next_back() {
            present(x) => { *x += 1 },
            none => { return 16 }
        }
    }

    var empty = [0; 0]
    {
        let empty_mut = mut empty
        match take empty_mut.split_at_mut_checked(0usize) {
            present(parts) => {
                if !parts.0.is_empty() || !parts.1.is_empty() { return 20 }
            },
            none => { return 20 }
        }
    }
    if values[0usize] != 10 || values[1usize] != 8 ||
        values[2usize] != 7 || values[4usize] != 6 {
        return 17
    }
    var limited_values = [1, 0, 2, 0, 3]
    var visits = 0usize
    {
        var limited = limited_values.splitn_mut(2usize, fn(read x: i32): bool {
            visits += 1usize
            x == 0
        })
        match take limited.next() {
            present(part) => {
                if part.len() != 1usize || part[0] != 1 { return 21 }
                part[0] = 10
            },
            none => { return 21 }
        }
        match take limited.next() {
            present(part) => {
                if part.len() != 3usize || part[0] != 2 || part[1] != 0 { return 22 }
                part[0] = 20
            },
            none => { return 22 }
        }
        if limited.next().is_present() { return 23 }
    }
    if visits != 2usize || limited_values[0] != 10 || limited_values[2] != 20 { return 24 }
    visits = 0usize
    {
        var limited = limited_values.rsplitn_mut(2usize, fn(read x: i32): bool {
            visits += 1usize
            x == 0
        })
        match take limited.next() {
            present(part) => {
                if part.len() != 1usize || part[0] != 3 { return 25 }
                part[0] = 30
            },
            none => { return 25 }
        }
        match take limited.next() {
            present(part) => {
                if part.len() != 3usize || part[0] != 10 || part[1] != 0 { return 26 }
                part[0] = 40
            },
            none => { return 26 }
        }
        if limited.next().is_present() { return 27 }
    }
    if visits != 2usize || limited_values[0] != 40 || limited_values[4] != 30 { return 28 }
    {
        var unlimited = limited_values.split_mut(fn(read x: i32): bool { x == 0 })
        match take unlimited.next_back() {
            present(part) => { if part.len() != 1usize || part[0] != 30 { return 29 } },
            none => { return 29 }
        }
        match take unlimited.next() {
            present(part) => { if part.len() != 1usize || part[0] != 40 { return 30 } },
            none => { return 30 }
        }
        match take unlimited.next_back() {
            present(part) => { if part.len() != 1usize || part[0] != 20 { return 31 } },
            none => { return 31 }
        }
        if unlimited.next().is_present() { return 32 }
    }
    0
}
