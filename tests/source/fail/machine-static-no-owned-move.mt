// expect-error: ownership 2:90 cannot move out of static
type Owner { value: i32 }; static VALUE: Owner = Owner(42); fn main() { let moved = take VALUE; 0 }
