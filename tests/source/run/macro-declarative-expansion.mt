macro square {
    ($x:expr) => { $x * $x };
}

macro largest {
    ($a:expr) => { $a };
    ($a:expr, $($rest:expr),+) => {
        pick(largest!($($rest),+), $a)
    };
}

macro total {
    ($($x:expr),*) => { 0 $(+ $x)* };
}

macro twice {
    ($s:stmt) => { $s; $s };
}

fn pick(a: i32, b: i32): i32 {
    if a > b { a } else { b }
}

fn main(): i32 {
    // an expr fragment keeps its grouping
    if square!(1 + 2) != 9 { return 1 }
    if largest!(3, 9, 4) != 9 { return 2 }
    if total!(1, 2, 3, 4) != 10 { return 3 }
    if total!() != 0 { return 4 }
    var count = 0
    twice!(count = count + 5)
    if count != 10 { return 5 }
    0
}
