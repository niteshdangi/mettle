// profiles: debug release
// String methods reached through its Text view: searching, splitting, trimming,
// case mapping, repetition and replacement, plus boundary queries.

import alloc.string.{String, concat}
import core.iter.{FromItems, Iterator}
import core.option
import std.panic.{catch_panic, CatchResult}

fn checks_search(): i32 {
    let s = String("a\u{e9}-b\u{e9}-")
    if !s.contains("\u{e9}") || s.contains("z") { return 1 }
    if !s.starts_with("a") || !s.ends_with("-") { return 2 }
    match s.find("\u{e9}") {
        present(i) => { if i != 1usize { return 3 } },
        none => { return 3 }
    }
    match s.rfind("\u{e9}") {
        present(i) => { if i != 5usize { return 4 } },
        none => { return 4 }
    }
    match s.strip_prefix("a") {
        present(rest) => { if rest != "\u{e9}-b\u{e9}-" { return 5 } },
        none => { return 5 }
    }
    if s.matches("\u{e9}").count() != 2usize { return 6 }
    0
}

fn checks_split(): i32 {
    let s = String("a,b,,c")
    if s.split(",").count() != 4usize { return 10 }
    if s.splitn(2usize, ",").count() != 2usize { return 11 }
    match s.split_once(",") {
        present(parts) => { if parts.0 != "a" || parts.1 != "b,,c" { return 12 } },
        none => { return 12 }
    }
    match s.rsplit_once(",") {
        present(parts) => { if parts.1 != "c" { return 13 } },
        none => { return 13 }
    }
    if String("x\ny\n").lines().count() != 2usize { return 14 }
    if String("a b  c").split_whitespace().count() != 3usize { return 15 }
    0
}

fn checks_trim_and_case(): i32 {
    let s = String("  Hi  ")
    if s.trim() != "Hi" || s.trim_start() != "Hi  " || s.trim_end() != "  Hi" { return 20 }
    if String("xxhixx").trim_matches("x") != "hi" { return 21 }
    if String("\u{e9}t\u{e9}").to_uppercase().as_text() != "\u{c9}T\u{c9}" { return 22 }
    if String("ABC").to_lowercase().as_text() != "abc" { return 23 }
    if String("ab").repeat(3usize).as_text() != "ababab" { return 24 }
    if String("aXa").replace("a", "b").as_text() != "bXb" { return 25 }
    if String("aaa").replacen("a", "b", 2usize).as_text() != "bba" { return 26 }
    0
}

fn checks_boundaries(): i32 {
    let s = String("h\u{e9}")
    if !s.is_char_boundary(0usize) || s.is_char_boundary(2usize) { return 30 }
    if s.floor_char_boundary(2usize) != 1usize || s.ceil_char_boundary(2usize) != 3usize { return 31 }
    match s.get(0usize, 1usize) {
        present(t) => { if t != "h" { return 32 } },
        none => { return 32 }
    }
    if s.get(0usize, 2usize).is_present() { return 33 }
    var count = 0usize
    var it = s.char_indices()
    while true {
        match it.next() {
            present(_) => { count += 1usize },
            none => { break }
        }
    }
    if count != 2usize || s.chars().count() != 2usize || s.bytes().count() != 3usize { return 34 }
    if concat("a", "b").len() != 2usize { return 35 }
    0
}

fn checks_remaining_forwarding(): Unit {
    let value = String("a\u{e9},b\u{e9},")
    var matches = value.match_indices('\u{e9}')
    assert(matches.next() == present((1usize, "\u{e9}")) &&
        matches.next_back() == present((5usize, "\u{e9}")) && matches.next().is_none(),
        "forwarded match indices retain original byte offsets")
    var reverse = value.rmatch_indices('\u{e9}')
    assert(reverse.next() == present((5usize, "\u{e9}")) &&
        reverse.next() == present((1usize, "\u{e9}")) && reverse.next().is_none(),
        "reverse match indices visit from the back")
    assert(value.rmatches('\u{e9}').count() == 2usize &&
        value.strip_suffix(",") == present("a\u{e9},b\u{e9}"), "reverse matches and suffix views use text forwarding")
    var split = value.rsplit(',')
    assert(split.next() == present("") && split.next() == present("b\u{e9}") &&
        split.next() == present("a\u{e9}") && split.next().is_none(), "reverse split preserves trailing empties")
    var limited = value.rsplitn(2usize, ',')
    assert(limited.next() == present("") && limited.next() == present("a\u{e9},b\u{e9}") &&
        limited.next().is_none(), "limited reverse splitting preserves the untouched prefix")
    var terminator = value.split_terminator(',')
    assert(terminator.next() == present("a\u{e9}") && terminator.next() == present("b\u{e9}") &&
        terminator.next().is_none(), "terminator split omits the trailing empty part")
    var reverse_terminator = value.rsplit_terminator(',')
    assert(reverse_terminator.next() == present("b\u{e9}") &&
        reverse_terminator.next() == present("a\u{e9}") && reverse_terminator.next().is_none(),
        "reverse terminator splitting preserves direction")
    var inclusive = value.split_inclusive(',')
    assert(inclusive.next() == present("a\u{e9},") && inclusive.next() == present("b\u{e9},") &&
        inclusive.next().is_none(), "inclusive split retains delimiters")
    let trimmed = String(" \tA\u{2003}B\n")
    assert(trimmed.trim_ascii() == "A\u{2003}B" && trimmed.trim_ascii_start() == "A\u{2003}B\n" &&
        trimmed.trim_ascii_end() == " \tA\u{2003}B", "ASCII trimming preserves non-ASCII spaces")
    assert(trimmed.eq_ignore_ascii_case(" \ta\u{2003}b\n") &&
        trimmed.to_ascii_lowercase().as_text() == " \ta\u{2003}b\n" &&
        trimmed.to_ascii_uppercase().as_text() == " \tA\u{2003}B\n", "ASCII case forwarding leaves Unicode unchanged")
    var whitespace = trimmed.split_ascii_whitespace()
    assert(whitespace.next() == present("A\u{2003}B") && whitespace.next().is_none(),
        "ASCII splitting does not treat Unicode-only whitespace as a separator")
    assert(String("xxbodyxx").trim_start_matches('x') == "bodyxx" &&
        String("xxbodyxx").trim_end_matches('x') == "xxbody", "one-sided trimming keeps the opposite boundary")
    assert(value.split_at_checked(2usize).is_none() &&
        value.split_at_checked(3usize) == present(("a\u{e9}", ",b\u{e9},")),
        "checked splitting rejects interior UTF-8 bytes")
    var mutable = String("ab")
    {
        let parts = mutable.split_at_mut(1usize)
        parts.0.make_ascii_uppercase()
        parts.1.make_ascii_uppercase()
    }
    assert(mutable.as_text() == "AB", "exclusive split results update disjoint source regions")
    var indexed = String("a\u{e9}b")
    {
        let middle = mut indexed[1usize..3usize]
        assert(middle == "\u{e9}", "exclusive range indexing retains whole UTF-8 scalars")
    }
    {
        let first = mut indexed[..=0usize]
        first.make_ascii_uppercase()
    }
    {
        let last = mut indexed[3usize..]
        last.make_ascii_uppercase()
    }
    {
        let empty = mut indexed[4usize..]
        assert(empty.is_empty(), "exclusive indexing permits the empty tail")
    }
    assert(indexed.as_text() == "A\u{e9}B", "exclusive range views mutate only selected bytes")
    let rejected = catch_panic(fn(): Unit {
        let invalid = mut indexed[2usize..3usize]
        let _ = invalid.len()
    })
    match rejected {
        CatchResult.Panicked(info) => assert(info.code() == 101 &&
            info.message() == "text slice is out of bounds or not on a character boundary",
            "exclusive indexing reports its UTF-8 boundary failure"),
        _ => assert(false, "exclusive indexing accepted an interior UTF-8 byte")
    }
    assert(indexed.as_text() == "A\u{e9}B", "failed exclusive indexing leaves the owner unchanged")
    let escaped = String("a\n")
    assert(String.(FromItems<char>).from_iter(escaped.escape_default()).as_text() == "a\\n" &&
        String.(FromItems<char>).from_iter(escaped.escape_debug()).as_text() == "a\\n",
        "escape adapters yield escaped content rather than original control characters")
    let unicode = String("\u{e9}")
    assert(String.(FromItems<char>).from_iter(unicode.escape_unicode()).as_text() == "\\u{e9}",
        "Unicode escape forwarding preserves scalar values")
    let supplementary = String("a\u{1f980}")
    var encoded = supplementary.encode_utf16()
    assert(encoded.next() == present(0x61u16) && encoded.next_back() == present(0xdd80u16) &&
        encoded.next_back() == present(0xd83eu16) && encoded.next().is_none(),
        "UTF-16 forwarding preserves surrogate pairs across mixed ends")
}

fn main(): i32 {
    checks_remaining_forwarding()
    let first = checks_search()
    if first != 0 { return first }
    let second = checks_split()
    if second != 0 { return second }
    let third = checks_trim_and_case()
    if third != 0 { return third }
    checks_boundaries()
}
