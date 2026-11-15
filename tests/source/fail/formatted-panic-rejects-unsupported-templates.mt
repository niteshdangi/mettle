// expect-error: type 12:9 formatted panic supports only sequential '{}' placeholders
// expect-error: type 14:9 formatted panic supports only sequential '{}' placeholders
// expect-error: type 16:9 formatted panic supports only sequential '{}' placeholders
// expect-error: type 18:9 formatted panic supports only sequential '{}' placeholders
// expect-error: type 20:9 formatted panic has more placeholders than arguments
// expect-error: type 22:9 formatted panic has more arguments than placeholders
// expect-error: type 24:9 unbalanced brace in formatted panic message
// expect-error: type 26:9 unbalanced brace in formatted panic message

fn main(): i32 {
    core.assert_matches!(0i32, 1,
        "{0}", 1i32)
    core.assert_matches!(0i32, 1,
        "{named}", 1i32)
    core.assert_matches!(0i32, 1,
        "{:?}", 1i32)
    core.assert_matches!(0i32, 1,
        "{:>8}", 1i32)
    core.assert_matches!(0i32, 1,
        "{} {}", 1i32)
    core.assert_matches!(0i32, 1,
        "{}", 1i32, 2i32)
    core.assert_matches!(0i32, 1,
        "{", 1i32)
    core.assert_matches!(0i32, 1,
        "}", 1i32)
    0
}
