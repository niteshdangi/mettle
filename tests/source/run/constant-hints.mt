const fn answer(): i32 {
    core.hint.cold_path()
    unsafe { core.hint.assert_unchecked(true) }
    if false { unsafe { core.hint.unreachable_unchecked() } }
    42
}

const ANSWER: i32 = answer()
fn main(): i32 { if ANSWER == 42 { 0 } else { 1 } }
