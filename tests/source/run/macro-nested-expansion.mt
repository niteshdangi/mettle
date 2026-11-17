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

macro forwarded_value {
    () => { add_one!(2) };
}

macro forwarded_again {
    () => { forwarded_value!() };
}

macro declaration {
    () => { fn declared(): i32 { 11 } };
}

macro forwarded_declaration {
    () => { declaration!() };
}

forwarded_declaration!()

fn main(): i32 {
    if add_three!(add_one!(1)) != 5 { return 1 }
    if classify!(0) != 0 { return 2 }
    if classify!(8) != 8 { return 3 }
    if 4 * forwarded_again!() != 12 { return 4 }
    if declared() != 11 { return 5 }
    0
}
