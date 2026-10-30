// expect-error-count: 1
// expect-error: signature 3:22 conflicting external
@export_name("same") static VALUE: i32 = 42; @export_name("same") fn answer(): i32 { 42 }; fn main() { 0 }
