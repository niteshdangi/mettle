// profiles: debug release
// String methods reached through its Text view: searching, splitting, trimming,
// case mapping, repetition and replacement, plus boundary queries.

import alloc.string.{String, concat}
import core.iter.Iterator
import core.option

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

fn main(): i32 {
    let first = checks_search()
    if first != 0 { return first }
    let second = checks_split()
    if second != 0 { return second }
    let third = checks_trim_and_case()
    if third != 0 { return third }
    checks_boundaries()
}
