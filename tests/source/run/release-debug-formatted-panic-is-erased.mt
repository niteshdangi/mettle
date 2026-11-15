// profiles: release
// expect-exit: 0
// expect-stderr: ""

static mut TRACE: i32 = 0

fn argument(value: i32): i32 {
    unsafe { TRACE = TRACE * 10 + value }
    value
}

fn main(): i32 {
    core.debug_assert_matches!(argument(1), 1 if argument(2) == 2,
        "pair={{{},{}}}", argument(3), argument(4))
    core.debug_assert_matches!(argument(5), 5,
        f"pair={argument(6)},{argument(7)}")
    if unsafe { TRACE } != 0 { return 1 }
    0
}
