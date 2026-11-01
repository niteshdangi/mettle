// profiles: debug release
// expect-error: unsafe 5:20 operation requires an unsafe block or unsafe function
// expect-error-count: 1
unsafe const fn echo(value: f32): f32 { value }
const VALUE: f32 = echo(1.25f32)
