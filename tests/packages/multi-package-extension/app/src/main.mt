make_fn!(answer)

@cfg(feature = "generated")
fn main(): i32 {
    answer() - 41 + generated.value() - 41 + mathlib.value() - 7
}

@cfg(not(feature = "generated"))
fn main(): i32 { 1 }
