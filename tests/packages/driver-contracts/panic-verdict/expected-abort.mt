extern "C" { unsafe fn raise(value: i32): i32; }

@test
@should_panic
fn abort_is_an_expected_panic() {
    unsafe { let _ = raise(6); }
}
