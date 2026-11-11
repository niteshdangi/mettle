// profiles: debug release
import core.iter.{Iterator, BidirectionalIterator}
import core.text.Text

fn is_piece(value: (read Text)?, read expected: Text): bool {
    match value { present(piece) => piece == expected, none => false }
}
fn main(): i32 {
    var split = "\u{e9}x".split("")
    assert(is_piece(split.next(), ""), "leading empty field")
    assert(is_piece(split.next(), "\u{e9}"), "multibyte scalar stays whole")
    assert(is_piece(split.next(), "x") && is_piece(split.next(), ""), "scalar and trailing empty")
    assert(split.next().is_none(), "empty pattern terminates")
    var empty = "".split("")
    assert(is_piece(empty.next(), "") && is_piece(empty.next(), ""), "both empty boundaries")
    assert(empty.next().is_none(), "empty boundaries exhausted")
    var limited = "\u{e9}x".splitn(2usize, "")
    assert(is_piece(limited.next(), "") && is_piece(limited.next(), "\u{e9}x"), "limited remainder")
    assert(limited.next().is_none(), "limited exhaustion")
    var reverse = "\u{e9}x".rsplitn(3usize, "")
    assert(is_piece(reverse.next(), "") && is_piece(reverse.next(), "x"), "reverse empty boundary")
    assert(is_piece(reverse.next(), "\u{e9}") && reverse.next().is_none(), "reverse remainder")
    var terminator = ",".rsplit_terminator(",")
    assert(is_piece(terminator.next(), "") && terminator.next().is_none(), "retain leading empty")
    assert("".split_terminator(",").next().is_none(), "empty forward terminator")
    assert("".rsplit_terminator(",").next().is_none(), "empty reverse terminator")
    assert("".split_inclusive(",").next().is_none(), "no phantom inclusive field")
    var char_split = "a,b,c".split(',')
    assert(is_piece(char_split.next(), "a") && is_piece(char_split.next_back(), "c"), "char mixed ends")
    assert(is_piece(char_split.next(), "b") && char_split.next_back().is_none(), "char no duplicate")
    var front = "ababa".match_indices("aba")
    var back = "ababa".rmatch_indices("aba")
    match front.next() { present(item) => assert(item.0 == 0usize, "forward overlapping choice"), none => panic("missing forward") }
    match back.next() { present(item) => assert(item.0 == 2usize, "reverse overlapping choice"), none => panic("missing reverse") }
    assert(front.next().is_none() && back.next().is_none(), "nonoverlapping traversal")
    let empty_values: [i32; 0] = []
    let xs: read [i32] = read empty_values
    assert(xs.split_inclusive(fn(read v: i32): bool { v == 0 }).next().is_none(), "empty inclusive slice")
    var mutable_empty: [i32; 0] = []
    let ys: mut [i32] = mut mutable_empty
    assert(ys.split_inclusive_mut(fn(read v: i32): bool { v == 0 }).next().is_none(), "empty mutable inclusive")
    let bytes = [11u8, 65u8, 11u8]
    let view: read [u8] = read bytes
    assert(view.trim_ascii().len() == 3usize, "vertical tab is not ASCII whitespace")
    assert(view.trim_ascii_start().len() == 3usize && view.trim_ascii_end().len() == 3usize, "one-sided whitespace")
    0
}
