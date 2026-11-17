fn wildcard(value: (
    bool, bool, bool, bool, bool, bool, bool, bool,
    bool, bool, bool, bool, bool, bool, bool, bool,
    bool, bool, bool, bool, bool, bool, bool, bool
)): i32 {
    match value { _ => 40 }
}

fn partitioned(value: (
    bool, bool, bool, bool, bool, bool, bool, bool,
    bool, bool, bool, bool, bool, bool, bool, bool,
    bool, bool, bool, bool, bool, bool, bool, bool
)): i32 {
    match value {
        (_, _, _, _, _, _, _, _, _, _, _, _,
         _, _, _, _, _, _, _, _, _, _, _, true) => 2,
        (_, _, _, _, _, _, _, _, _, _, _, _,
         _, _, _, _, _, _, _, _, _, _, _, false) => 1
    }
}

fn main() {
    let values = (
        false, true, false, true, false, true, false, true,
        true, false, true, false, true, false, true, false,
        false, false, false, false, true, true, true, true
    )
    if wildcard(values) + partitioned(values) == 42 &&
       partitioned((
           true, true, true, true, true, true, true, true,
           false, false, false, false, false, false, false, false,
           true, true, true, true, true, true, true, false
       )) == 1 { 0 } else { 1 }
}
