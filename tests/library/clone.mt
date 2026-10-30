import core.clone.Clone

fn main(): i32 {
    let a = (7, true)
    let b = a.clone()
    if b.0 != 7 || !b.1 { return 1 }
    let o: i64? = present(9i64)
    match o.clone() { present(v) => { if v != 9i64 { return 2 } }, none => { return 3 } }
    let n: u8? = none
    match n.clone() { present(_) => { return 4 }, none => {} }
    if 'x'.clone() != 'x' { return 5 }
    0
}
