fn expose<region r>(read owner: heap i32 from r): read i32 from r {
    read owner
}

fn expose_mut<region r>(mut owner: heap i32 from r): mut i32 from r {
    mut owner
}

fn main(): i32 {
    var owner = heap 40
    *expose_mut(owner) += 2
    if *expose(owner) == 42 { 0 } else { 1 }
}
