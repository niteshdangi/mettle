macro classify {
    ($value:path) => { 1 };
    ($value:ty) => { 2 };
}

fn main(): i32 {
    if classify!(module_name.TypeName) != 1 { return 1 }
    if classify!(module_name.Container<i32>.Member) != 1 { return 2 }
    if classify!((i32, i32)) != 2 { return 3 }
    if classify!([i32; 2]) != 2 { return 4 }
    0
}
