fn without_local_pattern(read text: Text): read Text from text {
    let pattern = alloc.string.from_text("..")
    text.trim_start_matches(pattern.as_text()).trim_end_matches(pattern.as_text())
}

fn main(): i32 {
    let text = "a\u{e9}b\u{1f600}a"
    assert(text.find('\u{e9}') == present(1usize), "scalar byte offset")
    assert(text.rfind('a') == present(8usize), "reverse scalar byte offset")
    assert(text.find(['\u{1f600}', '\u{e9}']) == present(1usize), "first character in set")
    let characters = ['\u{1f600}', '\u{e9}']
    assert(text.rfind(read characters) == present(4usize), "last character in borrowed set")
    assert(text.find("") == present(0usize) && text.rfind("") == present(text.len()), "empty pattern")
    assert("".find('a').is_none() && "".rfind('a').is_none(), "empty text has no scalar")
    assert(text.contains('\u{1f600}') && !text.contains('z'), "scalar containment")
    assert(text.starts_with(['z', 'a']) && text.ends_with('a'), "scalar boundary matches")
    assert(!text.starts_with('\u{e9}') && !text.ends_with('\u{1f600}'), "nonmatching boundary")
    assert(without_local_pattern("..x..") == "x", "returned view borrows text, not pattern")
    match text.strip_prefix('a') {
        present(part) => assert(part == "\u{e9}b\u{1f600}a", "scalar prefix removed once"),
        none => { return 1 }
    }
    match "\u{e9}\u{e9}".strip_suffix('\u{e9}') {
        present(part) => assert(part == "\u{e9}", "scalar suffix removed once"),
        none => { return 2 }
    }
    var visits = 0usize
    let first = text.find(fn(value: char): bool {
        visits += 1usize
        value == '\u{1f600}'
    })
    assert(first == present(4usize) && visits == 4usize, "forward predicate order and short circuit")
    visits = 0usize
    let last = text.rfind(fn(value: char): bool {
        visits += 1usize
        value == '\u{e9}'
    })
    assert(last == present(1usize) && visits == 4usize, "reverse predicate order and short circuit")
    assert("x".starts_with(fn(value: char): bool { visits += 1usize; value == 'x' }), "stateful boundary")
    assert(visits == 5usize, "boundary predicate called once")
    let empty = "".contains(fn(value: char): bool { visits += 1usize; true })
    assert(!empty && visits == 5usize, "empty searches do not call predicates")
    0
}
