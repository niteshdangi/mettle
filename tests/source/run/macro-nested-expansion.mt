macro add_one {
    ($x:expr) => { $x + 1 };
}

macro add_three {
    ($x:expr) => { add_one!(add_one!(add_one!($x))) };
}

macro classify {
    (0) => { 0 };
    ($n:literal) => { $n };
}

fn main(): i32 {
    if add_three!(add_one!(1)) != 5 { return 1 }
    if classify!(0) != 0 { return 2 }
    if classify!(8) != 8 { return 3 }
    0
}
