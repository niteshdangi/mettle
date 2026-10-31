import core.text.TextPattern

type DropPattern {
    counter: ptr<mut i32>
    target: char
    drop { unsafe { *self.counter += 1 } }
}

extend DropPattern implements TextPattern {
    mut fn matched_prefix(text: read Text): usize? {
        var chars = text.chars()
        match chars.next() {
            present(c) => { if c == self.target { present(c.len_utf8()) } else { none } },
            none => none
        }
    }
    mut fn matched_suffix(text: read Text): usize? {
        var chars = text.chars()
        match chars.next_back() {
            present(c) => { if c == self.target { present(c.len_utf8()) } else { none } },
            none => none
        }
    }
}

fn main(): i32 {
    // The iterator owns its pattern: it is dropped exactly once, with the
    // iterator, whether or not the iterator was exhausted.
    var drops = 0
    {
        var iterator = "a,b".split_by(DropPattern(core.ptr.from_mut(drops), ','))
        match iterator.next() { present(piece) => { if piece != "a" { return 1 } }, none => { return 1 } }
        if drops != 0 { return 2 }
    }
    if drops != 1 { return 3 }

    var exhausted_drops = 0
    {
        var iterator = "a,b".matches_by(DropPattern(core.ptr.from_mut(exhausted_drops), ','))
        match iterator.next() { present(_) => {}, none => { return 4 } }
        match iterator.next() { present(_) => { return 4 }, none => {} }
        if exhausted_drops != 0 { return 5 }
    }
    if exhausted_drops != 1 { return 6 }

    var reverse_drops = 0
    {
        var iterator = "a,b".rsplitn_by(2usize, DropPattern(core.ptr.from_mut(reverse_drops), ','))
        match iterator.next() { present(piece) => { if piece != "b" { return 7 } }, none => { return 7 } }
    }
    if reverse_drops != 1 { return 8 }
    0
}
