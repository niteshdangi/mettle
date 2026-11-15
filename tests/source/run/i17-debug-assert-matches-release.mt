// profiles: release
fn next(read calls: core.cell.Cell<i32>): i32 {
    calls.set(calls.get() + 1)
    calls.get()
}

fn main(): i32 {
    let calls = core.cell.Cell.new(0i32)
    core.debug_assert_matches!(1i32, 2i32, f"{next(read calls)} {next(read calls)}")
    std.debug_assert_matches!(1i32, 2i32, f"{next(read calls)} {next(read calls)}")
    core.debug_assert_matches!(1i32, 2i32, "{} {}", next(read calls), next(read calls))
    std.debug_assert_matches!(1i32, 2i32, "{} {}", next(read calls), next(read calls))
    if calls.get() != 0 { return 1 }
    0
}
