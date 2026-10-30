// expect-error: constant 2:63 element destructor
type Owner { value: i32; drop {} }; static EMPTY: [Owner;0] = [Owner(42);0]; fn main() { 0 }
