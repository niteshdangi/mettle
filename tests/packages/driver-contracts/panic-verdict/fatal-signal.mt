extern "C" { unsafe fn raise(value: i32): i32; }

@test
@should_panic
fn segmentation_fault_is_not_a_panic() {
    unsafe { let _ = raise(11); }
}
