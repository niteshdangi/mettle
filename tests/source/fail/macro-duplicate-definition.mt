// expect-error: macro 3:7 already defined
macro value { () => { 1 }; }
macro value { () => { 2 }; }
fn main(): i32 { 0 }
