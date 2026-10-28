fn main(): i32 {
    let value: (i32?)? = present(none)
    match take value {
        none => 1,
        present(none) => 0,
        present(present(_)) => 2
    }
}
