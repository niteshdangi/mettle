// expect-error: type 3:5 function address requires a function-pointer type or bound
fn address<F>(function: F): usize {
    core.intrinsics.fn_addr(function)
}
