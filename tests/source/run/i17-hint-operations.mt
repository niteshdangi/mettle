fn unchecked_unreachable(): Never {
    unsafe { core.hint.unreachable_unchecked() }
}

fn main(): i32 {
    core.hint.spin_loop()
    core.hint.cold_path()
    unsafe { core.hint.assert_unchecked(true) }
    if core.hint.select_unpredictable(true, 11i32, 13i32) != 11i32 { return 1 }
    0
}
