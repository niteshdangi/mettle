fn safe_value(): i32 { 42 }

fn main(): i32 {
    let operation: unsafe fn(): i32 = safe_value
    if unsafe { operation() } == 42 { 0 } else { 1 }
}
