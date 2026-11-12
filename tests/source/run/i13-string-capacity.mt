// profiles: debug release
// String capacity management: reserve and shrink behavior, and the fallible
// reservations reporting allocation failure without changing the contents.
import alloc.string

const HUGE: usize = 18446744073709551615usize

fn checks_reserve(): i32 {
    var text = string.from_text("ab")
    text.reserve(10usize)
    if text.capacity() < 12usize { return 1 }
    var exact = string.new()
    exact.reserve_exact(7usize)
    if exact.capacity() < 7usize || exact.len() != 0usize { return 2 }
    exact.push_str("abcdefg")
    if exact.capacity() < 7usize || exact.as_text() != "abcdefg" { return 3 }
    0
}

fn checks_shrink(): i32 {
    var text = string.with_capacity(64usize)
    text.push_str("hello")
    let before = text.capacity()
    text.shrink_to(16usize)
    if text.capacity() < 16usize || text.capacity() > before { return 10 }
    text.shrink_to(0usize)
    if text.capacity() < text.len() { return 11 }
    text.shrink_to_fit()
    if text.capacity() < 5usize || text.capacity() > before || text.as_text() != "hello" { return 12 }
    0
}

fn checks_try_reserve(): i32 {
    var text = string.from_text("keep")
    match take capture text.try_reserve(8usize) {
        success(_) => {},
        failure(_) => { return 20 }
    }
    if text.capacity() < 12usize { return 21 }
    match take capture text.try_reserve_exact(8usize) {
        success(_) => {},
        failure(_) => { return 22 }
    }
    match take capture text.try_reserve(HUGE) {
        success(_) => { return 23 },
        failure(_) => {}
    }
    match take capture text.try_reserve_exact(HUGE) {
        success(_) => { return 24 },
        failure(_) => {}
    }
    if text.as_text() != "keep" { return 25 }
    0
}

fn main(): i32 {
    let first = checks_reserve()
    if first != 0 { return first }
    let second = checks_shrink()
    if second != 0 { return second }
    checks_try_reserve()
}
