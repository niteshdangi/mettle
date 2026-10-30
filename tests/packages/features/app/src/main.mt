@cfg(feature = "fancy")
fn main(): i32 { widget::base() - 1 + extra::value() - 5 }
@cfg(not(feature = "fancy"))
fn main(): i32 { widget::base() - 100 }
