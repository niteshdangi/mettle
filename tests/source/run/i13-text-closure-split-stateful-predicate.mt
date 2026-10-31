fn main(): i32 {
    // The predicate sees each scalar once, in forward order, and the search
    // stops at the first match.
    var calls = 0usize
    {
        var iterator = "ab\u{e9},c".split_by(fn(value: char): bool {
            calls += 1usize
            value == ','
        })
        match iterator.next() {
            present(piece) => { if piece != "ab\u{e9}" { return 1 } },
            none => { return 1 }
        }
    }
    if calls != 4usize { return 2 }

    // Reverse search inspects scalars from the end, not the whole text.
    var reverse_calls = 0usize
    {
        var iterator = "a,b,c".split_by(fn(value: char): bool {
            reverse_calls += 1usize
            value == ','
        })
        match iterator.next_back() {
            present(piece) => { if piece != "c" { return 3 } },
            none => { return 3 }
        }
    }
    if reverse_calls != 2usize { return 4 }

    // Matching resumes after the previous match instead of rescanning.
    var match_calls = 0usize
    {
        var iterator = "xaxa".matches_by(fn(value: char): bool {
            match_calls += 1usize
            value == 'a'
        })
        match iterator.next() { present(_) => {}, none => { return 5 } }
        match iterator.next() { present(_) => {}, none => { return 5 } }
        match iterator.next() { present(_) => { return 5 }, none => {} }
    }
    if match_calls != 4usize { return 6 }
    0
}
