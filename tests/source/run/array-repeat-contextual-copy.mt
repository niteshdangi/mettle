fn inspect(read values: [i32?; 2]): i32 {
    match values[1] { none => 0, present(_) => 1 }
}

fn main(): i32 {
    let values: [i32?; 2] = [none; 2]
    let compact: [i32?; 65] = [none; 65]
    if inspect(values) != 0 || inspect([none; 2]) != 0 { return 1 }
    match compact[64] { none => 0, present(_) => 2 }
}
