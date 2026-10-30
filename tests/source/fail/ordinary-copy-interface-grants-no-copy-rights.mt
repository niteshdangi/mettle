// expect-error: ownership 4:40 cannot move out of a borrowed place

module fake { pub interface Copy {} }
fn wrong<T: fake::Copy>(value: T): T { value }
fn main(): i32 { 0 }
