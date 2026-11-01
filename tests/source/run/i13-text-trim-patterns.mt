fn main(): i32 {
    let text = "\u{e9}\u{e9}x\u{1f600}\u{1f600}"
    assert(text.trim_start_matches('\u{e9}') == "x\u{1f600}\u{1f600}", "scalar prefix")
    assert(text.trim_end_matches('\u{1f600}') == "\u{e9}\u{e9}x", "scalar suffix")
    assert("\u{e9}x\u{e9}".trim_matches('\u{e9}') == "x", "scalar both ends")
    assert("ababxabab".trim_matches("ab") == "x", "repeated text pattern")
    assert("x".trim_matches("") == "x", "empty pattern makes no progress")
    assert("".trim_matches("ab") == "", "empty text")
    assert("aaa".trim_matches('a') == "", "all matching")
    assert("abc".trim_matches('x') == "abc", "no matching scalar")

    var visits = 0usize
    let prefix = text.trim_start_matches(fn(value: char): bool {
        visits += 1usize
        value == '\u{e9}'
    })
    assert(prefix == "x\u{1f600}\u{1f600}" && visits == 3usize, "stateful prefix predicate")
    visits = 0usize
    let suffix = text.trim_end_matches(fn(value: char): bool {
        visits += 1usize
        value == '\u{1f600}'
    })
    assert(suffix == "\u{e9}\u{e9}x" && visits == 3usize, "stateful suffix predicate")
    visits = 0usize
    let middle = "\u{e9}x\u{1f600}".trim_matches(fn(value: char): bool {
        visits += 1usize
        value != 'x'
    })
    assert(middle == "x" && visits == 3usize, "same predicate state without revisiting a scalar")
    visits = 0usize
    let rejected = "x".trim_matches(fn(value: char): bool {
        visits += 1usize
        visits > 1usize
    })
    assert(rejected == "x" && visits == 1usize, "a rejected scalar is never tested twice")
    visits = 0usize
    let all = "\u{e9}\u{1f600}".trim_matches(fn(value: char): bool {
        visits += 1usize
        true
    })
    assert(all == "" && visits == 2usize, "fully trimmed text is not searched again")
    let empty = "".trim_matches(fn(value: char): bool {
        visits += 1usize
        true
    })
    assert(empty == "" && visits == 2usize, "empty text does not invoke predicate")
    let characters = ['\u{e9}', '\u{1f600}']
    assert(text.trim_matches(read characters) == "x", "borrowed character array")
    assert(text.trim_matches(read characters[0usize..2usize]) == "x", "character slice")
    assert(text.trim_matches(['\u{e9}', '\u{1f600}']) == "x", "owned character array")
    assert(text.trim_matches(['x'; 0]) == text, "empty character set")
    0
}
