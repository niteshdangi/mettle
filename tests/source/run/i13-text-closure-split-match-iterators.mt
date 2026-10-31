fn main(): i32 {
    let text = "a,\u{e9},b,,c"
    var pieces = text.split_by(',')
    let expected = ["a", "\u{e9}", "b", "", "c"]
    var index = 0usize
    while true {
        match pieces.next() {
            present(piece) => {
                if index >= 5usize || piece != expected[index] { return 1 }
                index += 1usize
            },
            none => { break }
        }
    }
    if index != 5usize { return 2 }
    match pieces.next() { present(_) => { return 3 }, none => {} }

    // Mixed-end consumption shares the same remaining text.
    var both = text.split_by(fn(value: char): bool { value == ',' })
    match both.next() { present(piece) => { if piece != "a" { return 4 } }, none => { return 4 } }
    match both.next_back() { present(piece) => { if piece != "c" { return 5 } }, none => { return 5 } }
    match both.next_back() { present(piece) => { if piece != "" { return 6 } }, none => { return 6 } }
    match both.next() { present(piece) => { if piece != "\u{e9}" { return 7 } }, none => { return 7 } }
    match both.next() { present(piece) => { if piece != "b" { return 8 } }, none => { return 8 } }
    match both.next() { present(_) => { return 9 }, none => {} }
    match both.next_back() { present(_) => { return 9 }, none => {} }

    var reversed = "x-y-z".rsplit_by('-')
    match reversed.next() { present(piece) => { if piece != "z" { return 10 } }, none => { return 10 } }
    match reversed.next() { present(piece) => { if piece != "y" { return 10 } }, none => { return 10 } }
    match reversed.next() { present(piece) => { if piece != "x" { return 10 } }, none => { return 10 } }
    match reversed.next() { present(_) => { return 10 }, none => {} }

    // No match yields the text once; empty text yields one empty piece.
    var whole = "abc".split_by('-')
    match whole.next() { present(piece) => { if piece != "abc" { return 11 } }, none => { return 11 } }
    match whole.next() { present(_) => { return 11 }, none => {} }
    var empty = "".split_by('-')
    match empty.next() { present(piece) => { if !piece.is_empty() { return 12 } }, none => { return 12 } }
    match empty.next() { present(_) => { return 12 }, none => {} }

    // splitn / rsplitn stop after `count` pieces and leave the remainder whole.
    var first_two = "a b c d".splitn_by(2usize, ' ')
    match first_two.next() { present(piece) => { if piece != "a" { return 13 } }, none => { return 13 } }
    match first_two.next() { present(piece) => { if piece != "b c d" { return 13 } }, none => { return 13 } }
    match first_two.next() { present(_) => { return 13 }, none => {} }
    var last_two = "a b c d".rsplitn_by(2usize, ' ')
    match last_two.next() { present(piece) => { if piece != "d" { return 14 } }, none => { return 14 } }
    match last_two.next() { present(piece) => { if piece != "a b c" { return 14 } }, none => { return 14 } }
    match last_two.next() { present(_) => { return 14 }, none => {} }
    var none_requested = "a b".splitn_by(0usize, ' ')
    match none_requested.next() { present(_) => { return 15 }, none => {} }

    // Terminator variants drop one trailing empty piece only.
    var terminated = "a,b,,".split_terminator_by(',')
    match terminated.next() { present(piece) => { if piece != "a" { return 16 } }, none => { return 16 } }
    match terminated.next() { present(piece) => { if piece != "b" { return 16 } }, none => { return 16 } }
    match terminated.next() { present(piece) => { if piece != "" { return 16 } }, none => { return 16 } }
    match terminated.next() { present(_) => { return 16 }, none => {} }
    var no_pieces = "".split_terminator_by(',')
    match no_pieces.next() { present(_) => { return 17 }, none => {} }
    var one_empty = ",".split_terminator_by(',')
    match one_empty.next() { present(piece) => { if !piece.is_empty() { return 18 } }, none => { return 18 } }
    match one_empty.next() { present(_) => { return 18 }, none => {} }
    var reverse_terminated = "a,b,".rsplit_terminator_by(',')
    match reverse_terminated.next() { present(piece) => { if piece != "b" { return 19 } }, none => { return 19 } }
    match reverse_terminated.next() { present(piece) => { if piece != "a" { return 19 } }, none => { return 19 } }
    match reverse_terminated.next() { present(_) => { return 19 }, none => {} }
    var reverse_one_empty = ",".rsplit_terminator_by(',')
    match reverse_one_empty.next() { present(piece) => { if !piece.is_empty() { return 20 } }, none => { return 20 } }
    match reverse_one_empty.next() { present(_) => { return 20 }, none => {} }
    var reverse_none = "".rsplit_terminator_by(',')
    match reverse_none.next() { present(_) => { return 21 }, none => {} }

    // Inclusive pieces keep the matching scalar and add no trailing empty piece.
    var inclusive = "a\nb\n".split_inclusive_by('\n')
    match inclusive.next() { present(piece) => { if piece != "a\n" { return 22 } }, none => { return 22 } }
    match inclusive.next() { present(piece) => { if piece != "b\n" { return 22 } }, none => { return 22 } }
    match inclusive.next() { present(_) => { return 22 }, none => {} }
    var inclusive_tail = "a\nb".split_inclusive_by('\n')
    match inclusive_tail.next() { present(piece) => { if piece != "a\n" { return 23 } }, none => { return 23 } }
    match inclusive_tail.next() { present(piece) => { if piece != "b" { return 23 } }, none => { return 23 } }
    var inclusive_empty = "".split_inclusive_by('\n')
    match inclusive_empty.next() { present(_) => { return 24 }, none => {} }

    // Matches and match_indices report byte offsets of multi-byte scalars.
    let accented = "\u{e9}a\u{e9}b"
    var found = accented.matches_by('\u{e9}')
    match found.next() { present(piece) => { if piece != "\u{e9}" { return 25 } }, none => { return 25 } }
    match found.next_back() { present(piece) => { if piece != "\u{e9}" { return 25 } }, none => { return 25 } }
    match found.next() { present(_) => { return 25 }, none => {} }
    var indices = accented.match_indices_by(fn(value: char): bool { value == '\u{e9}' })
    match indices.next() { present(item) => { if item.0 != 0usize || item.1 != "\u{e9}" { return 26 } }, none => { return 26 } }
    match indices.next() { present(item) => { if item.0 != 3usize || item.1 != "\u{e9}" { return 26 } }, none => { return 26 } }
    match indices.next() { present(_) => { return 26 }, none => {} }
    var reverse_indices = accented.rmatch_indices_by('\u{e9}')
    match reverse_indices.next() { present(item) => { if item.0 != 3usize { return 27 } }, none => { return 27 } }
    match reverse_indices.next() { present(item) => { if item.0 != 0usize { return 27 } }, none => { return 27 } }
    match reverse_indices.next() { present(_) => { return 27 }, none => {} }
    var reverse_matches = accented.rmatches_by('b')
    match reverse_matches.next() { present(piece) => { if piece != "b" { return 28 } }, none => { return 28 } }
    match reverse_matches.next() { present(_) => { return 28 }, none => {} }
    var absent = accented.matches_by('z')
    match absent.next() { present(_) => { return 29 }, none => {} }
    0
}
