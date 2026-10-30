// expect-error: type 6:26 a value of this type cannot fill an f-string hole
// expect-error-count: 1
import core.fmt.Message
type Opaque { id: i32 }
fn show(message: format Message): i32 { 0 }
fn main(): i32 { show(f"{Opaque(1)}") }
