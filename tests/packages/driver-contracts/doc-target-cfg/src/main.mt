@cfg(target_os = "linux")
pub module platform { pub fn answer(): i32 { 42 } }
import platform.answer
fn main(): i32 { answer() - 42 }
