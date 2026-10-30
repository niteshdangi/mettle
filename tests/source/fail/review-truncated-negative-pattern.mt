// truncated: the program ends mid-construct; diagnostics refer to its end
// expect-error-count: 1
// expect-error: parse 6:10 expected an integer literal after '-'
fn f(x:i32):i32 {
    match x {
        -