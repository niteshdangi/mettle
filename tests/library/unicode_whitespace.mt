import core.char

fn main(): i32 {
    if !'\u{85}'.is_whitespace() { return 1 }
    if !'\u{2007}'.is_whitespace() { return 2 }
    if !'\u{3000}'.is_whitespace() { return 3 }
    if '\u{200b}'.is_whitespace() { return 4 }
    if "\u{a0}\u{2007}mettle\u{3000}".trim() != "mettle" { return 5 }
    if "\u{2007}mettle\u{3000}".trim_start() != "mettle\u{3000}" { return 6 }
    if "\u{2007}mettle\u{3000}".trim_end() != "\u{2007}mettle" { return 7 }
    0
}
