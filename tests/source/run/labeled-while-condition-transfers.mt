
fn main() {
    var count = 0
    label again: while {
        count += 1
        if count < 3 { continue label again }
        if count == 3 { break label again }
        true
    } { return 1 }
    if count == 3 { 0 } else { 1 }
}
