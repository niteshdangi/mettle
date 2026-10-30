macro combine {
    ($a:expr, $b:expr) => {
        {
            let tmp = $a
            let other = $b
            tmp * 10 + other
        }
    };
}

macro declare_counter {
    () => { let $capture(counter) = 7 };
}

fn main(): i32 {
    let tmp = 3
    let other = 4
    // the macro's own tmp and other never capture the caller's
    let mixed = combine!(other, tmp)
    if mixed != 43 { return 1 }
    declare_counter!()
    if counter != 7 { return 2 }
    0
}
