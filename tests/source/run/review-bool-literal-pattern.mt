fn main(): i32 {
    if let (_, true) = (0, false) { return 1 }
    if let (_, false) = (0, true) { return 2 }
    if let (_, true) = (0, true) {} else { return 3 }
    if let (_, false) = (0, false) {} else { return 4 }
    0
}
