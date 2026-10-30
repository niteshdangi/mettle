// expect-error: name 2:56 unresolved value 'storage::VALUE'
module storage { static VALUE: i32 = 42; } fn main() { storage.VALUE; 0 }
