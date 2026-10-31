import core.char
import core.iter.Iterator

fn main(): i32 {
    if !'A'.is_alphabetic() || !'a'.is_lowercase() || !'A'.is_uppercase() {
        return 1
    }
    if !'9'.is_numeric() || !'9'.is_alphanumeric() || '!'.is_alphanumeric() {
        return 2
    }
    if !'\u{e9}'.is_alphabetic() || !'\u{e9}'.is_lowercase() ||
        !'\u{c0}'.is_uppercase() { return 3 }
    if !'\u{3b1}'.is_alphabetic() || !'\u{3a9}'.is_uppercase() ||
        !'\u{44f}'.is_lowercase() || !'\u{416}'.is_uppercase() { return 4 }
    if !'中'.is_alphabetic() || !'\u{663}'.is_numeric() ||
        !'\u{216b}'.is_numeric() || !'\u{bd}'.is_numeric() { return 5 }
    if !'\u{85}'.is_whitespace() || '\u{200b}'.is_whitespace() { return 6 }

    var upper = 'ß'.to_uppercase()
    match upper.next() {
        present(c) => { if c != 'S' { return 7 } },
        none => { return 8 }
    }
    match upper.next() {
        present(c) => { if c != 'S' { return 9 } },
        none => { return 10 }
    }
    match upper.next() {
        present(_) => { return 11 },
        none => {}
    }

    var lower = '\u{130}'.to_lowercase()
    match lower.next() {
        present(c) => { if c != 'i' { return 12 } },
        none => { return 13 }
    }
    match lower.next() {
        present(c) => { if c != '\u{307}' { return 14 } },
        none => { return 15 }
    }
    match lower.next() {
        present(_) => { return 16 },
        none => {}
    }
    0
}
