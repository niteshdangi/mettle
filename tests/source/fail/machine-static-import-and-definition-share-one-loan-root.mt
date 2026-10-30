// expect-error: ownership 2:195 access or storage lifetime conflicts with a live read loan
@export_name("counter") static mut COUNT: i32 = 1; extern "C" { @link_name("counter") static mut ALIAS: i32; } fn main() { let writer = unsafe { mut COUNT }; let reader = unsafe { read ALIAS }; *writer = 42; *reader }
