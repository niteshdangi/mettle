// expect-error: feature 2:12 pinned owning handles require the allocation library
fn invalid(value: pinned heap i32) {}
fn main() { 0 }
