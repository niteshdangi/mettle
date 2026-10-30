@cfg(feature = "generated")
fn main(): i32 { gen::value() - 7 }
@cfg(not(feature = "generated"))
fn main(): i32 { 1 }
