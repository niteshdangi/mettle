const fn replace_first(mut values: [i32; 4]): i32 {
    values[0] = 9
    9
}

const fn combine(values: [i32; 4], marker: i32): i32 {
    values[0] + marker
}

const fn snapshots(): i32 {
    var values: [i32; 4] = [1, 2, 3, 4]
    let frozen = values
    if combine(values, replace_first(mut values)) != 10 { return 1 }
    if frozen[0] != 1 || values[0] != 9 { return 2 }
    var nested = ([1i32, 2i32], [3i32, 4i32])
    let original = nested
    nested.0[1] = 7
    if original.0[1] != 2 || nested.0[1] != 7 { return 3 }
    let saved = nested
    nested.0[{ nested.0 = [8i32, 9i32]; 0usize }] = 6
    if saved.0[0] != 1 || saved.0[1] != 7 { return 4 }
    if nested.0[0] != 6 || nested.0[1] != 9 { return 5 }
    0
}

const RESULT: i32 = snapshots()
fn main(): i32 { RESULT }
