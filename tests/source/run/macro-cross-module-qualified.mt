module macro_cross_module_qualified {
    module first;
}

fn main(): i32 {
    macro_cross_module_qualified.first.value!() - 42
}
