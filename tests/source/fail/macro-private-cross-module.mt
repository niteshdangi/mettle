// expect-error: name 7:5 private macro 'value' is not visible from this module
module macro_private_cross_module {
    module first;
}

fn main(): i32 {
    macro_private_cross_module.first.value!()
}
