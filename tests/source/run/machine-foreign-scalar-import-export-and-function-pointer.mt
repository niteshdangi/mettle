
extern "C" {
    @link_name("abs")
    unsafe fn absolute(value: i32): i32;
    unsafe fn llabs(value: i64): i64;
}
@export_name("mettle_scalar_callback")
extern "C" fn callback(value: i8): i8 { value + 1 }
fn main() {
    let callback_pointer: extern "C" fn(i8): i8 = callback
    let magnitude = unsafe { absolute(-42) }
    let large = unsafe { llabs(-9223372036854775807i64) }
    if magnitude == 42 && callback_pointer(41) == 42i8 &&
       large == 9223372036854775807i64 { 0 } else { 1 }
}
