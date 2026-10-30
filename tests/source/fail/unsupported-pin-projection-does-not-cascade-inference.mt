// expect-error-count: 1
// expect-error: feature 3:98 pin projection of sum variants requires active-variant support
fn main(): i32 { var value: (u64)? = none; var handle = core.pin.Pin.new(mut value); let inner = handle.project_value(); 0 }
