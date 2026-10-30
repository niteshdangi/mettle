// expect-error: feature 3:9 derive(Default) is not implemented for enums
// expect-error-count: 1
@derive(Default)
enum Mode { Fast, Slow }
fn main(): i32 { 0 }
